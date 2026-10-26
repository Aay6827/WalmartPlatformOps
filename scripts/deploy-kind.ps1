# Deploys inventory and checkout to the local kind cluster with Helm.
#   .\scripts\deploy-kind.ps1                 # image tags come from deploy/helm/values/*.yaml
#   .\scripts\deploy-kind.ps1 -Tag abc1234    # override the tag (CI uses the commit sha)
#   .\scripts\deploy-kind.ps1 -LoadImages     # docker pull on the host + kind load (for private packages)
param(
    [string]$Tag = "",
    [string]$Context = "kind-walmartplatform",
    [string]$ClusterName = "walmartplatform",
    [switch]$LoadImages,
    [switch]$Force
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$chart = Join-Path $root "deploy/helm/service"

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
}

function Get-ValuesField {
    param([string]$Service, [string]$Field)
    $file = Join-Path $root "deploy/helm/values/$Service.yaml"
    $m = Select-String -Path $file -Pattern ('^\s*' + $Field + ':\s*"?([^"\s#]+)') | Select-Object -First 1
    if (-not $m) { throw "Could not read '$Field' from $file" }
    return $m.Matches[0].Groups[1].Value
}

function Test-GhcrPublic {
    param([string]$Repository, [string]$ImageTag)
    $path = $Repository -replace '^ghcr\.io/', ''
    try {
        $token = (Invoke-RestMethod "https://ghcr.io/token?scope=repository:${path}:pull").token
        $accept = "application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json"
        $r = Invoke-WebRequest "https://ghcr.io/v2/$path/manifests/$ImageTag" -Headers @{ Authorization = "Bearer $token"; Accept = $accept } -Method Head -UseBasicParsing
        return ($r.StatusCode -eq 200)
    } catch {
        return $false
    }
}

# Once Argo CD owns the services, a manual helm upgrade is undone by self-heal within seconds. CI has no Argo CD, so it is unaffected.
if (-not $Force) {
    $ErrorActionPreference = "Continue"
    & kubectl --context $Context -n argocd get application checkout -o name 2>&1 | Out-Null
    $argoOwnsIt = ($LASTEXITCODE -eq 0)
    $global:LASTEXITCODE = 0
    $ErrorActionPreference = "Stop"
    if ($argoOwnsIt) { throw "Argo CD owns these services on this cluster. Deploy with a git push instead (or pass -Force to override)." }
}

foreach ($svc in @('inventory', 'checkout')) {
    $repo = Get-ValuesField $svc 'repository'
    $imgTag = if ($Tag) { $Tag } else { Get-ValuesField $svc 'tag' }
    $image = "${repo}:${imgTag}"
    $values = Join-Path $root "deploy/helm/values/$svc.yaml"
    Write-Host "`n=== $svc ($image) ===" -ForegroundColor Cyan

    Invoke-Native helm @('lint', $chart, '-f', $values, '--set-string', "image.tag=$imgTag")
    Invoke-Native helm @('template', $svc, $chart, '-f', $values, '--set-string', "image.tag=$imgTag", '--namespace', 'platform') | Out-Null

    if ($LoadImages) {
        Invoke-Native docker @('pull', $image)
        Invoke-Native kind @('load', 'docker-image', $image, '--name', $ClusterName)
    } elseif (-not (Test-GhcrPublic $repo $imgTag)) {
        throw "Cannot pull $image anonymously. Either make the GHCR package public (GitHub profile > Packages > the package > Package settings > Change visibility), or re-run with -LoadImages."
    }

    Invoke-Native helm @('upgrade', '--install', $svc, $chart, '--namespace', 'platform', '--create-namespace',
        '-f', $values, '--set-string', "image.tag=$imgTag", '--kube-context', $Context, '--wait', '--timeout', '180s')
}

Write-Host "`n=== Deployed ===" -ForegroundColor Cyan
Invoke-Native kubectl @('--context', $Context, '-n', 'platform', 'get', 'deploy,pods,svc', '-o', 'wide')