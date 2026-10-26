# Gets a generated admin password out of its Kubernetes Secret without printing it to the terminal.
#   .\scripts\show-credentials.ps1                      # Argo CD admin password -> clipboard
#   .\scripts\show-credentials.ps1 -Service grafana     # Grafana admin password -> clipboard
#   .\scripts\show-credentials.ps1 -Print               # print it instead (do not paste terminal output into chats or screenshots)
param(
    [ValidateSet('argocd', 'grafana')][string]$Service = 'argocd',
    [switch]$Print,
    [string]$Context = "kind-walmartplatform"
)
$ErrorActionPreference = "Stop"

if ($Service -eq 'argocd') {
    $ns = 'argocd'; $secret = 'argocd-initial-admin-secret'; $key = 'password'; $user = 'admin'; $url = 'http://localhost:31002'
} else {
    $ns = 'monitoring'; $secret = 'grafana-admin'; $key = 'admin-password'; $user = 'admin'; $url = 'http://localhost:31001'
}

$ErrorActionPreference = "Continue"
$b64 = (& kubectl --context $Context -n $ns get secret $secret -o "jsonpath={.data.$key}" 2>$null) -join ""
$ErrorActionPreference = "Stop"
if (-not $b64) { throw "Secret $ns/$secret not found. Is the cluster up and $Service installed?" }
$password = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))

Write-Host "$Service  $url   user: $user"
$copied = $false
if (-not $Print) {
    try { Set-Clipboard -Value $password; $copied = $true } catch { $copied = $false }
}
if ($copied) {
    Write-Host "Password copied to the clipboard (not printed)." -ForegroundColor Green
} else {
    if (-not $Print) { Write-Host "No clipboard available here, printing instead:" -ForegroundColor Yellow }
    Write-Host "password: $password" -ForegroundColor Yellow
}