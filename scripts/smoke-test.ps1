# End-to-end checks against the kind deployment. -Chaos also takes inventory down and proves checkout degrades gracefully.
param(
    [string]$BaseUrl = "http://localhost:31000",
    [string]$Context = "kind-walmartplatform",
    [switch]$Chaos
)
$ErrorActionPreference = "Stop"
$script:failures = 0

function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) { Write-Host ("PASS  {0}  {1}" -f $Name, $Detail) -ForegroundColor Green }
    else { Write-Host ("FAIL  {0}  {1}" -f $Name, $Detail) -ForegroundColor Red; $script:failures++ }
}

function Invoke-Kubectl {
    & kubectl --context $Context @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl $($args -join ' ') failed with exit code $LASTEXITCODE" }
}

function Get-ViaProxy {
    param([string]$Service, [string]$Path)
    $out = & kubectl --context $Context get --raw "/api/v1/namespaces/platform/services/${Service}:http/proxy${Path}"
    if ($LASTEXITCODE -ne 0) { throw "API-server proxy call failed: $Service $Path" }
    return ($out -join "")
}

function Get-Stock {
    param([string]$Sku)
    return (Get-ViaProxy "inventory" "/stock/$Sku" | ConvertFrom-Json)
}

function Invoke-Checkout {
    param($Items)
    $body = @{ customer_id = "smoke"; items = $Items } | ConvertTo-Json -Depth 5 -Compress
    $code = 0
    $text = ""
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl/checkout" -Method Post -ContentType "application/json" -Body $body -UseBasicParsing -TimeoutSec 15
        $code = [int]$r.StatusCode
        $text = $r.Content
    } catch {
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        $text = "$($_.Exception.Message)"
    }
    $sw.Stop()
    return [pscustomobject]@{ Code = $code; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 2); Text = $text }
}

Write-Host "`n--- Smoke test against $BaseUrl ---" -ForegroundColor Cyan

$ready = Invoke-WebRequest "$BaseUrl/health/ready" -UseBasicParsing
Check "checkout readiness via NodePort" ($ready.StatusCode -eq 200) "HTTP $($ready.StatusCode)"

$before = (Get-Stock "WMT-1002").reserved
$r = Invoke-Checkout @(@{ sku = "WMT-1002"; quantity = 3 })
$after = (Get-Stock "WMT-1002").reserved
Check "checkout confirms an order" (($r.Code -eq 201) -and ($r.Text -match "CONFIRMED")) "HTTP $($r.Code)"
Check "inventory reserved the stock (checkout -> inventory inside the cluster)" ($after -eq ($before + 3)) "reserved $before -> $after"

$before = (Get-Stock "WMT-1003").reserved
$r = Invoke-Checkout @(@{ sku = "WMT-1003"; quantity = 5 }, @{ sku = "WMT-1008"; quantity = 999 })
$after = (Get-Stock "WMT-1003").reserved
Check "insufficient stock is rejected with 409" ($r.Code -eq 409) "HTTP $($r.Code)"
Check "partial reservation was rolled back" ($after -eq $before) "reserved $before -> $after"

$metrics = Get-ViaProxy "checkout" "/metrics"
Check "checkout exposes Prometheus metrics" ($metrics -match "checkout_requests_total") ""

if ($Chaos) {
    Write-Host "`n--- Chaos: scale inventory to 0 ---" -ForegroundColor Yellow
    Invoke-Kubectl -n platform scale deploy/inventory --replicas=0
    & kubectl --context $Context -n platform wait --for=delete pod -l app.kubernetes.io/name=inventory --timeout=90s 2>$null | Out-Null
    $global:LASTEXITCODE = 0

    $r = Invoke-Checkout @(@{ sku = "WMT-1001"; quantity = 1 })
    Check "checkout answers 503 (not a hang) when inventory is down" (($r.Code -eq 503) -and ($r.Seconds -lt 5)) "HTTP $($r.Code) in $($r.Seconds)s"
    $ready = Invoke-WebRequest "$BaseUrl/health/ready" -UseBasicParsing
    Check "checkout stays Ready (no cascading outage)" ($ready.StatusCode -eq 200) "HTTP $($ready.StatusCode)"

    Write-Host "`n--- Recovery: scale inventory back to 1 ---" -ForegroundColor Yellow
    Invoke-Kubectl -n platform scale deploy/inventory --replicas=1
    Invoke-Kubectl -n platform rollout status deploy/inventory --timeout=120s
    $recovered = $false
    for ($i = 0; $i -lt 10; $i++) {
        $r = Invoke-Checkout @(@{ sku = "WMT-1001"; quantity = 1 })
        if ($r.Code -eq 201) { $recovered = $true; break }
        Start-Sleep -Seconds 2
    }
    Check "checkout recovers on its own once inventory is back" $recovered "HTTP $($r.Code)"
}

if ($script:failures -gt 0) {
    Write-Host "`n$($script:failures) check(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll checks passed." -ForegroundColor Green