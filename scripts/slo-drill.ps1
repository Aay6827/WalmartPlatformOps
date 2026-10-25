# SLO drill: steady traffic -> take inventory down -> restore, while recording when each alert reacts.
# Writes the measured timings to docs/slo-drill-results.md.
param(
    [string]$BaseUrl = "http://localhost:31000",
    [string]$Prometheus = "http://localhost:31003",
    [string]$Context = "kind-walmartplatform",
    [int]$HealthySeconds = 60,
    [int]$OutageSeconds = 120,
    [int]$RecoverySeconds = 90
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Invoke-Kubectl {
    & kubectl --context $Context @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl $($args -join ' ') failed with exit code $LASTEXITCODE" }
}

function Get-AlertStates {
    $states = @{}
    try {
        $alerts = @((Invoke-RestMethod "$Prometheus/api/v1/alerts").data.alerts)
        foreach ($a in $alerts) { $states[$a.labels.alertname] = $a.state }
    } catch { }
    return $states
}

Write-Host "Resetting inventory (fresh in-memory stock) before the drill..." -ForegroundColor Cyan
Invoke-Kubectl -n platform rollout restart deploy/inventory
Invoke-Kubectl -n platform rollout status deploy/inventory --timeout=120s

$skus = @("WMT-1001", "WMT-1002", "WMT-1003", "WMT-1004", "WMT-1005", "WMT-1006", "WMT-1007")
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$phase = "healthy"
$outageAt = 0.0
$restoreAt = 0.0
$i = 0
$lastPoll = -10.0
$seen = @{}
$prev = @{}
$codes = @{}

Write-Host "`nPhase 1/3: healthy traffic for $HealthySeconds s (about 10 requests/s)" -ForegroundColor Cyan
while ($true) {
    $t = $clock.Elapsed.TotalSeconds
    if ($phase -eq "healthy" -and $t -ge $HealthySeconds) {
        $phase = "outage"; $outageAt = $t
        Write-Host ("`n[t={0:N1}s] Phase 2/3: INVENTORY DOWN for {1} s" -f $t, $OutageSeconds) -ForegroundColor Yellow
        Invoke-Kubectl -n platform scale deploy/inventory --replicas=0
    } elseif ($phase -eq "outage" -and $t -ge ($outageAt + $OutageSeconds)) {
        $phase = "recovery"; $restoreAt = $t
        Write-Host ("`n[t={0:N1}s] Phase 3/3: INVENTORY RESTORED, watching recovery for {1} s" -f $t, $RecoverySeconds) -ForegroundColor Cyan
        Invoke-Kubectl -n platform scale deploy/inventory --replicas=1
    } elseif ($phase -eq "recovery" -and $t -ge ($restoreAt + $RecoverySeconds)) {
        break
    }

    $body = '{"customer_id":"drill","items":[{"sku":"' + $skus[$i % 7] + '","quantity":1}]}'
    $i++
    $code = 0
    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl/checkout" -Method Post -ContentType "application/json" -Body $body -UseBasicParsing -TimeoutSec 10
        $code = [int]$r.StatusCode
    } catch {
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    }
    $key = "$phase $code"
    if ($codes.ContainsKey($key)) { $codes[$key]++ } else { $codes[$key] = 1 }

    if (($t - $lastPoll) -ge 2) {
        $lastPoll = $t
        $now = Get-AlertStates
        foreach ($name in $now.Keys) {
            $k = "$name|$($now[$name])"
            if (-not $seen.ContainsKey($k)) {
                $seen[$k] = $t
                Write-Host ("  [t={0,6:N1}s] {1} -> {2}" -f $t, $name, $now[$name])
            }
        }
        foreach ($name in @($prev.Keys)) {
            if ($prev[$name] -eq "firing" -and -not $now.ContainsKey($name)) {
                $seen["$name|resolved"] = $t
                Write-Host ("  [t={0,6:N1}s] {1} -> resolved" -f $t, $name) -ForegroundColor Green
            }
        }
        $prev = $now
    }
    Start-Sleep -Milliseconds 60
}

function Rel($name, $state, $origin) {
    $k = "$name|$state"
    if ($seen.ContainsKey($k)) { return ("{0:N0} s" -f ($seen[$k] - $origin)) }
    return "not reached"
}

$rows = @()
foreach ($name in @("CheckoutFastBurn", "CheckoutSlowBurn", "InventoryDependencyDown", "PlatformTargetDown")) {
    $rows += ("| {0} | {1} | {2} | {3} |" -f $name, (Rel $name "pending" $outageAt), (Rel $name "firing" $outageAt), (Rel $name "resolved" $restoreAt))
}
$counts = ($codes.Keys | Sort-Object | ForEach-Object { "{0}: {1}" -f $_, $codes[$_] }) -join "; "

$md = @(
    "# SLO drill results",
    "",
    "Measured on the local kind cluster on $(Get-Date -Format 'yyyy-MM-dd HH:mm') (scrape and evaluation interval 5 s).",
    "",
    "Scenario: about 10 checkout requests/s for $HealthySeconds s, inventory scaled to 0 for $OutageSeconds s, then restored.",
    "",
    "| Alert | Pending after outage began | Firing after outage began | Resolved after restore |",
    "|---|---|---|---|"
) + $rows + @(
    "",
    "Requests by phase and status: $counts",
    "",
    "Notes: CheckoutSlowBurn uses a 30-minute window, so it keeps firing long after recovery; that is expected, not a bug.",
    "The windows are scaled down for the drill (see deploy/monitoring/slo.rules.yml)."
)
$out = Join-Path $root "docs/slo-drill-results.md"
[System.IO.File]::WriteAllText($out, ($md -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))

Write-Host "`n=== Drill summary ===" -ForegroundColor Cyan
Write-Host "Requests: $counts"
$rows | ForEach-Object { Write-Host $_ }
Write-Host "`nWritten to docs/slo-drill-results.md" -ForegroundColor Green