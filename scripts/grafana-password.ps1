param([string]$Context = "kind-walmartplatform")
$b64 = & kubectl --context $Context -n monitoring get secret grafana-admin -o 'jsonpath={.data.admin-password}'
if ($LASTEXITCODE -ne 0 -or -not $b64) { throw "Secret grafana-admin not found. Run .\scripts\deploy-monitoring.ps1 first." }
Write-Host ("admin / " + [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)))