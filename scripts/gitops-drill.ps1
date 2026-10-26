# Two GitOps drills against the running cluster. Writes docs/gitops-drill-results.md.
#   1. Drift: change the cluster by hand (scale inventory to 3). Argo CD should put it back.
#   2. Deploy and rollback through git only: change a checkout setting, push, watch it roll out, git revert, watch it roll back.
# Needs: Argo CD installed (install-argocd.ps1) and a clean, pushed git working tree. Takes a few minutes.
# The drill commits carry [skip ci] so they do not start the CI pipeline.
param(
    [string]$Context = "kind-walmartplatform",
    [int]$TimeoutSeconds = 240
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$valuesRel = "deploy/helm/values/checkout.yaml"
$valuesFile = Join-Path $root $valuesRel
$reportRel = "docs/gitops-drill-results.md"

function Invoke-Git {
    param([string[]]$GitArgs)
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $out = & git -C $root @GitArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    $text = ($out | ForEach-Object { "$_" }) -join "`n"
    if ($code -ne 0) { throw "git $($GitArgs -join ' ') failed ($code): $text" }
    return $text
}

function Invoke-Kubectl {
    param([string[]]$KubectlArgs)
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $out = & kubectl --context $Context @KubectlArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    $text = ($out | ForEach-Object { "$_" }) -join "`n"
    if ($code -ne 0) { throw "kubectl $($KubectlArgs -join ' ') failed ($code): $text" }
    return $text
}

function Get-AppSync {
    param([string]$Name)
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $out = & kubectl --context $Context -n argocd get application $Name -o "jsonpath={.status.sync.status}/{.status.health.status}" 2>$null
    $ErrorActionPreference = $old
    return ($out -join "")
}

function Get-Replicas {
    param([string]$Deploy)
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $out = & kubectl --context $Context -n platform get deploy $Deploy -o "jsonpath={.spec.replicas}" 2>$null
    $ErrorActionPreference = $old
    return (($out -join "").Trim())
}

function Get-CheckoutTimeout {
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $json = & kubectl --context $Context -n platform get deploy checkout -o json 2>$null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($code -ne 0 -or -not $json) { return "" }
    $d = ($json -join "`n") | ConvertFrom-Json
    foreach ($e in @($d.spec.template.spec.containers[0].env)) { if ($e -and $e.name -eq 'INVENTORY_TIMEOUT_SECONDS') { return [string]$e.value } }
    return ""
}

function Wait-Until {
    param([scriptblock]$Condition, [int]$Seconds)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
        if (& $Condition) { return [math]::Round($sw.Elapsed.TotalSeconds, 1) }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

# ---- preconditions ----
foreach ($app in @('inventory', 'checkout')) {
    $s = Get-AppSync $app
    if ($s -ne 'Synced/Healthy') { throw "Argo application '$app' is '$s', not Synced/Healthy. Run .\scripts\install-argocd.ps1 first." }
}
if (Invoke-Git @('status', '--porcelain')) { throw "The git working tree has uncommitted changes. Commit or stash them first." }
[void](Invoke-Git @('pull', '--rebase', '-q'))
$original = [System.IO.File]::ReadAllText($valuesFile)
if (-not $original.Contains('INVENTORY_TIMEOUT_SECONDS: "2.0"')) { throw "Expected INVENTORY_TIMEOUT_SECONDS: `"2.0`" in $valuesRel (the drill changes it to 2.5 and back)." }

# ---- drill 1: drift ----
Write-Host "`n=== Drill 1: manual change (kubectl scale inventory to 3) ===" -ForegroundColor Cyan
[void](Invoke-Kubectl @('-n', 'platform', 'scale', 'deploy/inventory', '--replicas=3'))
Write-Host "Cluster now has inventory replicas = $(Get-Replicas 'inventory'). Waiting for Argo CD to undo it..."
$healSeconds = Wait-Until { (Get-Replicas 'inventory') -eq '1' } $TimeoutSeconds
if ($null -eq $healSeconds) { throw "Argo CD did not restore inventory to 1 replica within $TimeoutSeconds s." }
Write-Host "Reverted by Argo CD after $healSeconds s." -ForegroundColor Green

# ---- drill 2: change through git, then roll back through git ----
Write-Host "`n=== Drill 2a: change through git (INVENTORY_TIMEOUT_SECONDS 2.0 -> 2.5) ===" -ForegroundColor Cyan
$changed = $original.Replace('INVENTORY_TIMEOUT_SECONDS: "2.0"', 'INVENTORY_TIMEOUT_SECONDS: "2.5"')
[System.IO.File]::WriteAllText($valuesFile, $changed, (New-Object System.Text.UTF8Encoding($false)))
[void](Invoke-Git @('add', $valuesRel))
[void](Invoke-Git @('commit', '-q', '-m', 'drill: raise checkout inventory timeout to 2.5 s [skip ci]'))
[void](Invoke-Git @('push', '-q'))
$pushed = Get-Date
Write-Host "Pushed. Waiting for Argo CD to roll it out (it checks git every 30 s)..."
$appliedSeconds = Wait-Until { (Get-CheckoutTimeout) -eq '2.5' } $TimeoutSeconds
if ($null -eq $appliedSeconds) { throw "The change did not reach the cluster within $TimeoutSeconds s. Is the push on GitHub, and is Argo CD able to read the repo?" }
[void](Invoke-Kubectl @('-n', 'platform', 'rollout', 'status', 'deploy/checkout', '--timeout=180s'))
$rolledSeconds = [math]::Round(((Get-Date) - $pushed).TotalSeconds, 1)
Write-Host "Config reached the Deployment after $appliedSeconds s; rollout finished $rolledSeconds s after the push." -ForegroundColor Green

Write-Host "`n=== Drill 2b: roll back with git revert ===" -ForegroundColor Cyan
[void](Invoke-Git @('revert', '--no-edit', 'HEAD'))
[void](Invoke-Git @('push', '-q'))
$pushed = Get-Date
$revertAppliedSeconds = Wait-Until { (Get-CheckoutTimeout) -eq '2.0' } $TimeoutSeconds
if ($null -eq $revertAppliedSeconds) { throw "The revert did not reach the cluster within $TimeoutSeconds s." }
[void](Invoke-Kubectl @('-n', 'platform', 'rollout', 'status', 'deploy/checkout', '--timeout=180s'))
$revertRolledSeconds = [math]::Round(((Get-Date) - $pushed).TotalSeconds, 1)
Write-Host "Rolled back: config reverted after $revertAppliedSeconds s; rollout finished $revertRolledSeconds s after the push." -ForegroundColor Green

# ---- report ----
$final = Get-AppSync 'checkout'
$lines = @(
    "# GitOps drill results",
    "",
    "Run on $(Get-Date -Format 'yyyy-MM-dd HH:mm') against the local kind cluster. Argo CD checks git every 30 s here (the default is 3 minutes), so these times include up to 30 s of waiting for that poll.",
    "",
    "| Drill | What happened | Time |",
    "|---|---|---|",
    "| Drift | ``kubectl scale deploy/inventory --replicas=3`` by hand; Argo CD (selfHeal) restored 1 replica | $healSeconds s |",
    "| Deploy by git | Pushed ``INVENTORY_TIMEOUT_SECONDS`` 2.0 -> 2.5; value reached the Deployment | $appliedSeconds s |",
    "| Deploy by git | Rolling update of checkout finished | $rolledSeconds s after the push |",
    "| Rollback by git | ``git revert`` pushed; value back to 2.0 | $revertAppliedSeconds s |",
    "| Rollback by git | Rolling update finished | $revertRolledSeconds s after the push |",
    "",
    "Final state of the checkout application: **$final**.",
    "",
    "Nothing was applied with kubectl or helm during drills 2a and 2b: the only inputs were two commits and two pushes. The drill commits are tagged ``[skip ci]``, so CI did not run for them."
)
[System.IO.File]::WriteAllText((Join-Path $root $reportRel), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
[void](Invoke-Git @('add', $reportRel))
[void](Invoke-Git @('commit', '-q', '-m', 'docs: GitOps drill results [skip ci]'))
[void](Invoke-Git @('push', '-q'))
Write-Host "`nWritten to $reportRel and pushed." -ForegroundColor Green