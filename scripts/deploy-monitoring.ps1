# Deploys Prometheus + Grafana (namespace "monitoring") and waits until Prometheus is scraping the platform pods.
# Run after deploy-kind.ps1: Prometheus needs the "platform" namespace to exist.
param([string]$Context = "kind-walmartplatform")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "deploy/monitoring"

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
}

Invoke-Native kubectl @('--context', $Context, 'apply', '-f', (Join-Path $dir 'namespace.yaml'))

# The Grafana admin password is generated per cluster and lives only in a Kubernetes Secret, never in git.
$ErrorActionPreference = "Continue"
& kubectl --context $Context -n monitoring get secret grafana-admin -o name 2>&1 | Out-Null
$secretExists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = "Stop"
if (-not $secretExists) {
    $bytes = New-Object byte[] 18
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $password = ([Convert]::ToBase64String($bytes)) -replace '[+/=]', 'x'
    Invoke-Native kubectl @('--context', $Context, '-n', 'monitoring', 'create', 'secret', 'generic', 'grafana-admin',
        '--from-literal=admin-user=admin', "--from-literal=admin-password=$password")
    Write-Host "`nGrafana login: admin / $password" -ForegroundColor Yellow
    Write-Host "(Show it again any time with .\scripts\grafana-password.ps1)" -ForegroundColor Yellow
}

Invoke-Native kubectl @('--context', $Context, 'apply', '-k', $dir)
Invoke-Native kubectl @('--context', $Context, '-n', 'monitoring', 'rollout', 'status', 'deploy/prometheus', '--timeout=180s')
Invoke-Native kubectl @('--context', $Context, '-n', 'monitoring', 'rollout', 'status', 'deploy/grafana', '--timeout=180s')

Write-Host "`nWaiting for Prometheus to discover and scrape the platform pods..." -ForegroundColor Cyan
$healthy = 0
$total = 0
for ($i = 0; $i -lt 30; $i++) {
    try {
        $targets = @((Invoke-RestMethod "http://localhost:31003/api/v1/targets").data.activeTargets)
        $total = $targets.Count
        $healthy = @($targets | Where-Object { $_.health -eq 'up' }).Count
        if ($total -ge 3 -and $healthy -eq $total) { break }
    } catch { }
    Start-Sleep -Seconds 3
}
Write-Host "Prometheus targets up: $healthy / $total (expected 3: 2x checkout + 1x inventory)"
if ($total -lt 3 -or $healthy -ne $total) { throw "Prometheus is not scraping all platform pods yet. Open http://localhost:31003/targets" }

Write-Host "`nPrometheus: http://localhost:31003   (alerts: /alerts)" -ForegroundColor Green
Write-Host "Grafana:    http://localhost:31001   (dashboard: Platform > Checkout SLO)" -ForegroundColor Green