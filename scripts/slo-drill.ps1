# SLO drill: steady traffic -> take inventory down -> restore, while recording when each alert reacts
# and how long requests really take in each phase. Writes the measurements to docs/slo-drill-results.md.
param(
    [string]$BaseUrl = "http://localhost:31000",
    [string]$Prometheus = "http://localhost:31003",
    [string]$Context = "kind-walmartplatform",
    [int]$HealthySeconds = 240,
    [int]$OutageSeconds = 150,
    [int]$RecoverySeconds = 120
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
Write-Host "Letting Prometheus settle for 20 s..."
Start-Sleep -Seconds 20

$skus = @("WMT-1001", "WMT-1002", "WMT-1003", "WMT-1004", "WMT-1005", "WMT-1006", "WMT-1007")
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$phase = "healthy"
$outageAt = 0.0
$restoreAt = 0.0
$i = 0
$lastPoll = -10.0
$seen = @{}
$prev = @{}
$lat = @{}

Write-Host "`nPhase 1/3: healthy traffic for $HealthySeconds s" -ForegroundColor Cyan
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
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl/checkout" -Method Post -ContentType "application/json" -Body $body -UseBasicParsing -TimeoutSec 15
        $code = [int]$r.StatusCode
    } catch {
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    }
    $sw.Stop()
    $key = "$phase|$code"
    if (-not $lat.ContainsKey($key)) { $lat[$key] = New-Object System.Collections.ArrayList }
    [void]$lat[$key].Add($sw.Elapsed.TotalSeconds)

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
$endAt = $clock.Elapsed.TotalSeconds

function Rel($name, $state, $origin) {
    $k = "$name|$state"
    if (-not $seen.ContainsKey($k)) { return "not reached" }
    $d = $seen[$k] - $origin
    if ($d -lt 0) { return "before the outage (noise from the inventory restart)" }
    return ("{0:N0} s" -f $d)
}

$alertRows = @()
foreach ($name in @("CheckoutFastBurn", "CheckoutSlowBurn", "CheckoutLatencySLO", "InventoryDependencyDown", "InventoryAbsent", "PlatformTargetDown")) {
    $alertRows += ("| {0} | {1} | {2} | {3} |" -f $name, (Rel $name "pending" $outageAt), (Rel $name "firing" $outageAt), (Rel $name "resolved" $restoreAt))
}

$durations = @{ healthy = $outageAt; outage = ($restoreAt - $outageAt); recovery = ($endAt - $restoreAt) }
$latRows = @()
foreach ($ph in @("healthy", "outage", "recovery")) {
    $keys = @($lat.Keys | Where-Object { $_ -like "$ph|*" } | Sort-Object)
    $phaseTotal = 0
    foreach ($k in $keys) { $phaseTotal += $lat[$k].Count }
    foreach ($k in $keys) {
        $vals = @($lat[$k] | Sort-Object)
        $n = $vals.Count
        $med = $vals[[int][math]::Floor(($n - 1) / 2)]
        $p95 = $vals[[int][math]::Min($n - 1, [math]::Ceiling(0.95 * $n) - 1)]
        $max = $vals[$n - 1]
        $status = $k.Split('|')[1]
        $latRows += ("| {0} | {1:N1} | {2} | {3} | {4:N3} | {5:N3} | {6:N3} |" -f $ph, ($phaseTotal / $durations[$ph]), $status, $n, $med, $p95, $max)
    }
}

$md = @(
    "# SLO drill results",
    "",
    "Measured on the local kind cluster on $(Get-Date -Format 'yyyy-MM-dd HH:mm') (Prometheus scrape and rule evaluation every 5 s).",
    "",
    "Scenario: steady checkout traffic for $HealthySeconds s, inventory scaled to 0 for $OutageSeconds s, then restored and watched for $RecoverySeconds s. Alert times are seconds after the outage began (resolved: seconds after inventory was restored).",
    "",
    "| Alert | Pending | Firing | Resolved |",
    "|---|---|---|---|"
) + $alertRows + @(
    "",
    "Request latency as seen by the client, per phase and HTTP status (seconds):",
    "",
    "| Phase | Requests/s (all statuses) | HTTP status | Requests | Median | p95 | Max |",
    "|---|---|---|---|---|---|---|"
) + $latRows + @(
    "",
    "Notes: CheckoutSlowBurn uses a 30-minute window, so it can keep firing long after recovery; that is expected.",
    "The burn-rate windows are scaled down for the drill (see deploy/monitoring/slo.rules.yml and docs/slo.md)."
)
$out = Join-Path $root "docs/slo-drill-results.md"
[System.IO.File]::WriteAllText($out, ($md -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))

Write-Host "`n=== Drill summary ===" -ForegroundColor Cyan
$alertRows | ForEach-Object { Write-Host $_ }
Write-Host ""
$latRows | ForEach-Object { Write-Host $_ }
Write-Host "`nWritten to docs/slo-drill-results.md" -ForegroundColor Green