# Runs the k6 checkout load test and watches the checkout HPA while it runs.
# Writes docs/load-test-results.md with the k6 summary and what the autoscaler did.
#   .\scripts\load-test.ps1                      # warm 30s, ramp 60s to 120 req/s, hold 120s, cool 30s
#   .\scripts\load-test.ps1 -PeakRps 200
# Uses k6 from PATH if installed (winget install GrafanaLabs.k6), otherwise runs it in Docker.
param(
    [int]$PeakRps = 120,
    [int]$BaseRps = 10,
    [string]$Warm = "30s",
    [string]$Ramp = "60s",
    [string]$Hold = "120s",
    [string]$Cool = "30s",
    [int]$ScaleDownWaitSeconds = 240,
    [string]$Context = "kind-walmartplatform",
    [string]$K6Image = "grafana/k6:latest",
    [string]$ReportPath = "docs/load-test-results.md"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root "load-tests/checkout.js"
$outDir = Join-Path $root "load-tests/out"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stdoutFile = Join-Path $outDir "k6-stdout.txt"
$stderrFile = Join-Path $outDir "k6-stderr.txt"

function Get-HpaSample {
    $ErrorActionPreference = "Continue"
    $json = & kubectl --context $Context -n platform get hpa checkout -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
    $h = ($json -join "`n") | ConvertFrom-Json
    $cpu = $null
    foreach ($m in @($h.status.currentMetrics)) {
        if ($m -and $m.type -eq 'Resource' -and $m.resource.name -eq 'cpu') { $cpu = $m.resource.current.averageUtilization }
    }
    return [pscustomobject]@{
        Current = [int]$h.status.currentReplicas
        Desired = [int]$h.status.desiredReplicas
        Cpu     = $cpu
        Min     = [int]$h.spec.minReplicas
        Max     = [int]$h.spec.maxReplicas
        Target  = [int]$h.spec.metrics[0].resource.target.averageUtilization
    }
}

# ---- preflight ----
$first = Get-HpaSample
if (-not $first) { throw "No HPA named 'checkout' in namespace platform. Run .\scripts\deploy-kind.ps1 first (autoscaling is enabled in deploy/helm/values/checkout.yaml)." }
$ErrorActionPreference = "Continue"
& kubectl --context $Context top pods -n platform 2>&1 | Out-Null
$topOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = "Stop"
if (-not $topOk) { throw "kubectl top fails, so the HPA has no CPU numbers. Run .\scripts\install-metrics-server.ps1 first." }
try {
    $ready = Invoke-WebRequest "http://localhost:31000/health/ready" -UseBasicParsing
    if ($ready.StatusCode -ne 200) { throw "HTTP $($ready.StatusCode)" }
} catch { throw "checkout is not answering on http://localhost:31000 ($($_.Exception.Message))." }

# ---- start k6 ----
$k6Cmd = Get-Command k6 -ErrorAction SilentlyContinue
$runner = ""
$envArgs = "-e PEAK_RPS=$PeakRps -e BASE_RPS=$BaseRps -e WARM=$Warm -e RAMP=$Ramp -e HOLD=$Hold -e COOL=$Cool"
if ($k6Cmd) {
    $runner = "k6 (local install)"
    $exe = $k6Cmd.Source
    $argLine = "run --no-color --quiet -e BASE_URL=http://localhost:31000 $envArgs `"$script`""
    $startArgs = @{ FilePath = $exe; ArgumentList = $argLine }
} else {
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCmd) { throw "Neither k6 nor docker was found. Install k6 with: winget install GrafanaLabs.k6" }
    $runner = "Docker image $K6Image"
    Write-Host "k6 is not installed locally; running it as $K6Image (first run pulls the image)." -ForegroundColor Yellow
    $argLine = "run --rm -i $K6Image run --no-color --quiet -e BASE_URL=http://host.docker.internal:31000 $envArgs -"
    $startArgs = @{ FilePath = $dockerCmd.Source; ArgumentList = $argLine; RedirectStandardInput = $script }
}

Write-Host "`n=== k6: $BaseRps -> $PeakRps req/s on POST /checkout  (warm $Warm, ramp $Ramp, hold $Hold, cool $Cool) ===" -ForegroundColor Cyan
Write-Host "Runner: $runner. Grafana: http://localhost:31001 (Platform > Checkout scaling and load)" -ForegroundColor Cyan
$started = Get-Date
$proc = Start-Process @startArgs -NoNewWindow -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
$null = $proc.Handle   # keeps ExitCode readable on Windows PowerShell 5.1

# ---- watch the autoscaler while k6 runs, then until it has scaled back down ----
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$samples = New-Object System.Collections.ArrayList
function Add-Sample {
    $s = Get-HpaSample
    if (-not $s) { return $null }
    $row = [pscustomobject]@{ T = [int]$sw.Elapsed.TotalSeconds; Current = $s.Current; Desired = $s.Desired; Cpu = $s.Cpu; Min = $s.Min; Max = $s.Max; Target = $s.Target }
    [void]$samples.Add($row)
    $cpuText = if ($null -ne $row.Cpu) { "$($row.Cpu)%" } else { "n/a" }
    Write-Host ("  t={0,4}s  replicas {1} (desired {2})  cpu {3} of {4}% target" -f $row.T, $row.Current, $row.Desired, $cpuText, $row.Target)
    return $row
}
while (-not $proc.HasExited) {
    [void](Add-Sample)
    Start-Sleep -Seconds 10
}
$proc.WaitForExit()
$k6Exit = $proc.ExitCode
$k6EndT = [int]$sw.Elapsed.TotalSeconds
Write-Host "`nk6 finished (exit code $k6Exit). Watching scale-down for up to $ScaleDownWaitSeconds s..." -ForegroundColor Cyan
$limit = $sw.Elapsed.TotalSeconds + $ScaleDownWaitSeconds
while ($sw.Elapsed.TotalSeconds -lt $limit) {
    $row = Add-Sample
    if ($row -and $row.Current -le $row.Min -and $row.Desired -le $row.Min) { break }
    Start-Sleep -Seconds 10
}

# ---- analysis ----
$summary = ""
if (Test-Path $stdoutFile) { $summary = (Get-Content $stdoutFile -Raw -Encoding UTF8) }
$errText = ""
if (Test-Path $stderrFile) { $errText = (Get-Content $stderrFile -Raw -Encoding UTF8) }
if ($null -eq $summary) { $summary = "" }
if ($null -eq $errText) { $errText = "" }

$verdict = if ($k6Exit -eq 0) { "PASS - every threshold held" } elseif ($k6Exit -eq 99) { "FAIL - at least one threshold was crossed" } else { "ERROR - k6 exited with code $k6Exit" }
$min = if ($samples.Count -gt 0) { $samples[0].Min } else { 2 }
$peak = if ($samples.Count -gt 0) { ($samples | Measure-Object -Property Current -Maximum).Maximum } else { 0 }
$up = $samples | Where-Object { $_.Desired -gt $_.Min } | Select-Object -First 1
$peakRow = $samples | Where-Object { $_.Current -eq $peak } | Select-Object -First 1
$back = $null
if ($peakRow) { $back = $samples | Where-Object { $_.T -gt $peakRow.T -and $_.Current -le $_.Min } | Select-Object -First 1 }
$upText = if ($up) { "first scale-up decision at t=$($up.T) s" } else { "never wanted more than $min replicas" }
$peakText = if ($peakRow) { "peak $peak replicas, first reached at t=$($peakRow.T) s" } else { "no samples" }
$backText = if ($back) { "back to $min replicas at t=$($back.T) s" } else { "not back to $min replicas within the watch window" }

$ncpu = ""
$ErrorActionPreference = "Continue"
$dockerInfo = @(& docker info --format '{{.NCPU}} {{.MemTotal}}' 2>$null) -join ""
if ($dockerInfo -match '^(\d+)\s+(\d+)$') { $ncpu = "{0} CPUs, {1:N1} GiB RAM" -f [int]$Matches[1], ([double]$Matches[2] / 1GB) } else { $ncpu = "unknown" }
$ErrorActionPreference = "Stop"

$lines = New-Object System.Collections.ArrayList
[void]$lines.Add("# Checkout load test results")
[void]$lines.Add("")
[void]$lines.Add("Run on $($started.ToString('yyyy-MM-dd HH:mm')) against the local kind cluster. **$verdict.**")
[void]$lines.Add("")
[void]$lines.Add("- Load: $BaseRps req/s -> $PeakRps req/s (open model, ``ramping-arrival-rate``), warm $Warm, ramp $Ramp, hold $Hold, cool $Cool. Every request is ``POST /checkout`` and must return 201.")
[void]$lines.Add("- Pass/fail thresholds are the checkout SLOs: failed requests < 0.5%, p95 < 500 ms, and no dropped iterations (k6 itself kept up).")
[void]$lines.Add("- Autoscaler: $min to $($samples[0].Max) replicas, CPU target $($samples[0].Target)% of the 100m request. Observed: $upText; $peakText; $backText.")
[void]$lines.Add("- Runner: $runner. Docker Desktop: $ncpu. k6, kind, Prometheus, Grafana and the services all share this one machine, so absolute numbers are indicative only.")
[void]$lines.Add("")
[void]$lines.Add("## Autoscaler timeline")
[void]$lines.Add("")
[void]$lines.Add("k6 ended at t=$k6EndT s.")
[void]$lines.Add("")
[void]$lines.Add("| t (s) | replicas | desired | CPU vs request (target $($samples[0].Target)%) |")
[void]$lines.Add("|---|---|---|---|")
foreach ($r in $samples) {
    $c = if ($null -ne $r.Cpu) { "$($r.Cpu)%" } else { "n/a" }
    [void]$lines.Add("| $($r.T) | $($r.Current) | $($r.Desired) | $c |")
}
[void]$lines.Add("")
[void]$lines.Add("## k6 summary")
[void]$lines.Add("")
[void]$lines.Add('```text')
[void]$lines.Add($summary.TrimEnd())
if ($errText.Trim()) { [void]$lines.Add(""); [void]$lines.Add("--- k6 log (stderr) ---"); [void]$lines.Add($errText.TrimEnd()) }
[void]$lines.Add('```')
[void]$lines.Add("")
$reportFull = Join-Path $root $ReportPath
New-Item -ItemType Directory -Force -Path (Split-Path $reportFull -Parent) | Out-Null
[System.IO.File]::WriteAllText($reportFull, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "`n=== $verdict ===" -ForegroundColor $(if ($k6Exit -eq 0) { 'Green' } else { 'Yellow' })
Write-Host "Autoscaler: $upText; $peakText; $backText."
Write-Host "Written to $ReportPath"
exit $k6Exit