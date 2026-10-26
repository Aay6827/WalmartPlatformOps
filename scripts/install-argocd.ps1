# Installs Argo CD on the kind cluster and hands the platform over to it (GitOps).
#   .\scripts\install-argocd.ps1
# Prerequisite: deploy/argocd/** is pushed to GitHub (Argo reads the apps from git, not from this folder).
# Needs internet access from the cluster and from kubectl (the Argo manifest is pinned by URL in deploy/argocd/kustomization.yaml).
param(
    [string]$Context = "kind-walmartplatform",
    [int]$SyncTimeoutSeconds = 480
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
}

function Get-AppStatus {
    param([string]$Name)
    $ErrorActionPreference = "Continue"
    $json = & kubectl --context $Context -n argocd get application $Name -o json 2>$null
    $code = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($code -ne 0 -or -not $json) { return [pscustomobject]@{ Name = $Name; Sync = "missing"; Health = "missing"; Revision = "" } }
    $a = ($json -join "`n") | ConvertFrom-Json
    $rev = ""
    if ($a.status -and $a.status.sync -and $a.status.sync.revision) { $rev = ([string]$a.status.sync.revision).Substring(0, 7) }
    $sync = "Unknown"; $health = "Unknown"
    if ($a.status -and $a.status.sync -and $a.status.sync.status) { $sync = [string]$a.status.sync.status }
    if ($a.status -and $a.status.health -and $a.status.health.status) { $health = [string]$a.status.health.status }
    return [pscustomobject]@{ Name = $Name; Sync = $sync; Health = $health; Revision = $rev }
}

# ---- 1. the apps must already be in git, because Argo clones the repo ----
$ErrorActionPreference = "Continue"
& git -C $root fetch origin main -q 2>&1 | Out-Null
& git -C $root cat-file -e "origin/main:deploy/argocd/apps/checkout.yaml" 2>&1 | Out-Null
$inGit = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = "Stop"
if (-not $inGit) { throw "deploy/argocd/apps/checkout.yaml is not on origin/main yet. Commit and push first: Argo CD deploys from GitHub, not from this folder." }

# ---- 2. install Argo CD ----
Write-Host "`n=== Installing Argo CD ===" -ForegroundColor Cyan
Invoke-Native kubectl @('--context', $Context, 'apply', '-k', (Join-Path $root 'deploy/argocd'), '--server-side', '--force-conflicts')
foreach ($d in @('argocd-redis', 'argocd-repo-server', 'argocd-applicationset-controller', 'argocd-server')) {
    Invoke-Native kubectl @('--context', $Context, '-n', 'argocd', 'rollout', 'status', "deploy/$d", '--timeout=300s')
}
Invoke-Native kubectl @('--context', $Context, '-n', 'argocd', 'rollout', 'status', 'statefulset/argocd-application-controller', '--timeout=300s')
Invoke-Native kubectl @('--context', $Context, 'wait', '--for=condition=established', 'crd/applications.argoproj.io', '--timeout=60s')

# ---- 3. the one object applied by hand: the root app ----
Write-Host "`n=== Handing over to Argo CD (app of apps) ===" -ForegroundColor Cyan
Invoke-Native kubectl @('--context', $Context, 'apply', '-f', (Join-Path $root 'deploy/argocd/root-app.yaml'))

Write-Host "Waiting for platform-root, inventory, checkout and monitoring to be Synced and Healthy..."
$names = @('platform-root', 'inventory', 'checkout', 'monitoring')
$deadline = (Get-Date).AddSeconds($SyncTimeoutSeconds)
$rows = @()
while ((Get-Date) -lt $deadline) {
    $rows = @($names | ForEach-Object { Get-AppStatus $_ })
    $ready = @($rows | Where-Object { $_.Sync -eq 'Synced' -and $_.Health -eq 'Healthy' }).Count
    if ($ready -eq $names.Count) { break }
    Start-Sleep -Seconds 5
}
Write-Host ""
$rows | Format-Table Name, Sync, Health, Revision -AutoSize | Out-String | Write-Host
$notReady = @($rows | Where-Object { $_.Sync -ne 'Synced' -or $_.Health -ne 'Healthy' })
if ($notReady.Count -gt 0) {
    Write-Host "Not ready yet: $(($notReady | ForEach-Object { $_.Name }) -join ', '). Look at the failing app with:" -ForegroundColor Yellow
    Write-Host "  kubectl -n argocd describe application $($notReady[0].Name)" -ForegroundColor Yellow
    throw "Argo CD applications did not all become Synced and Healthy within $SyncTimeoutSeconds s."
}

# ---- 4. login details ----
$ErrorActionPreference = "Continue"
$b64 = (& kubectl --context $Context -n argocd get secret argocd-initial-admin-secret -o "jsonpath={.data.password}" 2>$null) -join ""
$ErrorActionPreference = "Stop"
Write-Host "Argo CD:  http://localhost:31002" -ForegroundColor Green
if ($b64) {
    $password = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
    Write-Host "Login:    admin / $password" -ForegroundColor Yellow
    Write-Host "(The password is generated for this cluster and lives only in a Kubernetes Secret.)"
}
Write-Host "`nFrom now on a git push is the deployment. Do not use deploy-kind.ps1 on this cluster (it refuses unless forced)." -ForegroundColor Green