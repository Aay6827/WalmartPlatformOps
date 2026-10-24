# Runs pytest per service. Both packages are called "app", so they cannot share one pytest process.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$venv = Join-Path $root ".venv"
if (-not (Test-Path $venv)) { python -m venv $venv }
$py = Join-Path $venv "Scripts\python.exe"
$failed = @()
foreach ($svc in "inventory", "checkout") {
    $dir = Join-Path $root "services\$svc"
    Write-Host "== $svc" -ForegroundColor Cyan
    & $py -m pip install -q -r (Join-Path $dir "requirements-dev.txt")
    Push-Location $dir
    & $py -m pytest
    if ($LASTEXITCODE -ne 0) { $failed += $svc }
    Pop-Location
}
if ($failed.Count -gt 0) { Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "All services passed." -ForegroundColor Green