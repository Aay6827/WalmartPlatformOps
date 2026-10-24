$ctx = 'kind-walmartplatform'
$existing = kind get clusters 2>$null
if ($existing -contains 'walmartplatform') {
    Write-Host "Cluster 'walmartplatform' already exists; reusing it."
} else {
    Write-Host "Creating the kind cluster (first run downloads about 1 GB)..."
    kind create cluster --config deploy\kind\kind-config.yaml --wait 180s
    if ($LASTEXITCODE -ne 0) {
        Write-Host "kind create cluster failed. Paste the output above." -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n--- Nodes ---"
kubectl --context $ctx get nodes -o wide

Write-Host "`n--- Port mapping check: temporary nginx on node port 31000 ---"
kubectl --context $ctx apply -f deploy\kind\portcheck.yaml
kubectl --context $ctx rollout status deployment/portcheck --timeout=180s
Start-Sleep -Seconds 3
try {
    $r = Invoke-WebRequest http://localhost:31000 -UseBasicParsing -TimeoutSec 10
    Write-Host ("Port 31000 reachable from Windows: HTTP {0}" -f $r.StatusCode) -ForegroundColor Green
} catch {
    Write-Host ("Port 31000 NOT reachable: " + $_.Exception.Message) -ForegroundColor Red
}
kubectl --context $ctx delete -f deploy\kind\portcheck.yaml --ignore-not-found