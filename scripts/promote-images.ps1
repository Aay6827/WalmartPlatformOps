# Waits until CI has pushed both images for a commit to GHCR, then points the Helm values at that commit.
# This is the manual version of "CI bumps the image tag in git"; Argo CD (next block) then deploys from git.
#   .\scripts\promote-images.ps1                # uses the current commit (HEAD)
#   .\scripts\promote-images.ps1 -Tag abc1234   # a specific commit
param(
    [string]$Tag = "",
    [int]$TimeoutSeconds = 720
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $Tag) { $Tag = ((& git -C $root rev-parse HEAD) | Select-Object -First 1).Substring(0, 7) }

function Get-ValuesField {
    param([string]$Service, [string]$Field)
    $file = Join-Path $root "deploy/helm/values/$Service.yaml"
    $m = Select-String -Path $file -Pattern ('^\s*' + $Field + ':\s*"?([^"\s#]+)') | Select-Object -First 1
    if (-not $m) { throw "Could not read '$Field' from $file" }
    return $m.Matches[0].Groups[1].Value
}

function Test-GhcrImage {
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

$services = @('inventory', 'checkout')
Write-Host "Waiting for CI to publish images tagged $Tag (up to $TimeoutSeconds s)..." -ForegroundColor Cyan
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$ready = @{}
while ($ready.Count -lt $services.Count) {
    foreach ($svc in $services) {
        if (-not $ready.ContainsKey($svc) -and (Test-GhcrImage (Get-ValuesField $svc 'repository') $Tag)) {
            $ready[$svc] = $true
            Write-Host ("  {0}: image {1} is published" -f $svc, $Tag) -ForegroundColor Green
        }
    }
    if ($ready.Count -eq $services.Count) { break }
    if ($clock.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
        throw "Timed out waiting for images tagged $Tag. Check the CI run: https://github.com/Aay6827/WalmartPlatformOps/actions"
    }
    Write-Host ("  ...still waiting ({0:N0}s). CI has to pass lint, tests and the Trivy scan first." -f $clock.Elapsed.TotalSeconds)
    Start-Sleep -Seconds 15
}

foreach ($svc in $services) {
    $file = Join-Path $root "deploy/helm/values/$svc.yaml"
    $text = [System.IO.File]::ReadAllText($file)
    $new = [regex]::Replace($text, '(?m)^(\s*tag:\s*)"?[^"\s#]+"?', ('${1}"' + $Tag + '"'))
    [System.IO.File]::WriteAllText($file, $new, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  $svc values now use tag $Tag"
}