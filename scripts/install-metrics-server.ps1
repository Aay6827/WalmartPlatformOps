# Installs metrics-server on the kind cluster so the HPA (and "kubectl top") can see CPU usage.
#   .\scripts\install-metrics-server.ps1
param([string]$Context = "kind-walmartplatform")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
}

Invoke-Native kubectl @('--context', $Context, 'apply', '-k', (Join-Path $root 'deploy/metrics-server'))
Invoke-Native kubectl @('--context', $Context, '-n', 'kube-system', 'rollout', 'status', 'deploy/metrics-server', '--timeout=180s')

Write-Host "`nWaiting for the first CPU numbers (metrics-server scrapes every 15 s)..." -ForegroundColor Cyan
$ok = $false
$ErrorActionPreference = "Continue"
for ($i = 0; $i -lt 30; $i++) {
    & kubectl --context $Context top nodes 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $ok = $true; break }
    Start-Sleep -Seconds 5
}
$ErrorActionPreference = "Stop"
if (-not $ok) { throw "metrics-server is running but 'kubectl top nodes' still fails. Check: kubectl -n kube-system logs deploy/metrics-server" }
Invoke-Native kubectl @('--context', $Context, 'top', 'nodes')
Write-Host "`nmetrics-server is working." -ForegroundColor Green