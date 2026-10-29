# WalmartPlatformOps

A small retail checkout platform built to show the whole platform-engineering loop on one laptop: build, scan, test, deploy by git push, observe against SLOs, break it on purpose, fix it, and write down what was learned. It is a portfolio project, not affiliated with any retailer.

Everything runs on a local [kind](https://kind.sigs.k8s.io/) cluster. Every number below was measured on that cluster and comes from a file in this repo; where I could not prove something, the doc says so.

## What was measured

| Question | Result | Evidence |
|---|---|---|
| Does checkout hold its SLOs from 10 to 120 req/s? | **Yes.** 20,550 requests, 0 failed, p95 7.26 ms (SLO: 500 ms), 0 dropped iterations. | [load-test-results.md](docs/load-test-results.md) |
| Does the autoscaler add capacity in time? | 2 pods to 5 pods (limit 6). First scale-up decision 111 s into the run, 5 pods at 152 s, back to 2 pods at 384 s (k6 ended at 252 s). | [load-test-results.md](docs/load-test-results.md) |
| What happens past the autoscaler's limit? | At a 300 req/s target the autoscaler reached its 6-pod limit at t=112 s and the test **failed**: k6 completed 30,935 requests (about 129/s averaged over the run) and dropped 19,314 more, p95 was 5.1 s (SLO: 500 ms), and 27 of 30,936 requests (0.08%) failed with a connection EOF. | [load-test-results-300rps.md](docs/load-test-results-300rps.md) |
| Does Argo CD undo a manual `kubectl scale`? | Yes, in 0.8 s. | [gitops-drill-results.md](docs/gitops-drill-results.md) |
| How fast does a git change reach a running pod? | Config in the Deployment after 25.6 s, rollout finished 34.5 s after the push. | [gitops-drill-results.md](docs/gitops-drill-results.md) |
| How fast does `git revert` roll it back? | Config reverted after 53.1 s, rollout finished 61.9 s after the push. | [gitops-drill-results.md](docs/gitops-drill-results.md) |
| What happens when inventory goes down? | Checkout answers 503 in 48 ms median (53 ms p95) instead of about 1 s; the page alert fires 49 s after the outage starts. | [RCA-001](docs/rca/001-slow-503s-during-inventory-outage.md) |
| Does the cluster refuse an insecure pod? | Yes: a privileged pod in `platform` is rejected by Pod Security Admission (`restricted`). | [security.md](docs/security.md) |

Each GitOps timing is a single run, not an average. The load test shares one machine with the cluster, Prometheus, Grafana and k6, so absolute latencies are indicative only. Checkout is a light in-memory service, which is why latency stays so low; the autoscaler reacts because the CPU request is deliberately small (100m).

**Same test, four runs.** The 120 req/s test is borderline on this laptop. On Oct 26 it passed with p95 7.26 ms. Three runs on Oct 29 gave two failures and one pass, and in every one of them errors were 0.00% and p95 was 40-46 ms, far inside the 500 ms SLO. The only threshold that tripped was the strict `dropped_iterations` check (19 and 45 of about 20,550 iterations), which counts iterations k6 could not start on time. Worst-case latency on Oct 29 was 0.5-1.4 s against 93 ms on Oct 26, and I do not know where those spikes come from. A rollout (Argo CD applying CI's promote commit) landed mid-run in two of the three, but the run without one failed too, so rollouts do not explain it. k6 had only 50 virtual users ready, and at 120 req/s a half-second stall needs about 60, so drops follow from any spike; the script now preallocates 200. Details: [docs/load-testing.md](docs/load-testing.md).

## Screenshots

![Checkout scaling dashboard during the load test](docs/img/grafana-scaling.png)

![Argo CD application tree](docs/img/argocd-tree.png)

![Firing alerts during the inventory outage drill](docs/img/alert-firing.png)

## Architecture

```text
                      git push
                         |
                         v
   GitHub Actions: lint, tests, image build + Trivy scan, Helm/kustomize validation,
   config scan, secret scan, throwaway kind cluster deploy + smoke test + outage drill
                         |  (only if green)
                         v
        "promote" job commits the new image tag into deploy/helm/values/*.yaml
                         |
                         v
   Argo CD (app of apps) watches the repo and syncs the cluster, with prune and self-heal
                         |
          +--------------+---------------+
          v              v               v
      checkout  --->  inventory      monitoring
   (FastAPI, HPA     (FastAPI)     Prometheus + Grafana
    2-6 pods,                      SLO burn-rate alerts
    circuit breaker)
```

- **Services:** `checkout` (`POST /checkout`, `GET /orders/{id}`) calls `inventory` (stock, reserve, release). Both expose `/health/live`, `/health/ready` and Prometheus `/metrics`. State is in memory, so inventory runs as a single replica.
- **One generic Helm chart** (`deploy/helm/service`) with a values file per service: probes, resource limits, PodDisruptionBudget, an optional HPA, and a hardened pod spec.
- **Argo CD** installs `inventory`, `checkout` and `monitoring` from a root app. Nobody runs `helm upgrade` or `kubectl apply` against the cluster. See [gitops.md](docs/gitops.md).

## Reliability

- **SLOs:** checkout availability 99.5% and latency (95% under 500 ms), with multi-window burn-rate alerts, runbooks, and promtool unit tests that also run in CI. See [slo.md](docs/slo.md).
- **A real finding:** the first outage drill showed 503s taking about a second each and throughput dropping from 6.4/s to 1.3/s. A circuit breaker and a 0.5 s connect timeout fixed it. The root cause is **not proven**; the RCA labels the two candidate explanations as hypotheses. See [RCA-001](docs/rca/001-slow-503s-during-inventory-outage.md).
- **The drill also exposed an alerting gap:** `up == 0` cannot fire for a pod that disappeared, so `InventoryAbsent` was added and unit-tested.

## Security

Trivy image scan, Trivy config scan of the rendered manifests and Dockerfiles, gitleaks over the full git history, Pod Security `restricted` on the `platform` namespace, non-root read-only pods with all capabilities dropped, admin passwords copied to the clipboard rather than printed, and Dependabot. Each scan found something real when first run and the fixes are listed in [security.md](docs/security.md), including what is **not** covered (no NetworkPolicies, no image signing, secrets not encrypted at rest, no Terraform).

## Run it

Requirements: Docker Desktop, [kind](https://kind.sigs.k8s.io/), kubectl, PowerShell. Windows PowerShell 5.1 is what I developed on.

```powershell
.\scripts\deploy-kind.ps1            # create the cluster and deploy (first time only)
.\scripts\install-metrics-server.ps1 # CPU metrics for the autoscaler
.\scripts\install-argocd.ps1         # hand the platform over to Argo CD (needs the repo pushed to GitHub)
.\scripts\deploy-monitoring.ps1      # Prometheus and Grafana (skip if Argo CD manages monitoring)
.\scripts\smoke-test.ps1             # end-to-end check
.\scripts\slo-drill.ps1              # break inventory on purpose, watch the alerts
.\scripts\load-test.ps1              # k6 load test and autoscaler timeline
.\scripts\gitops-drill.ps1           # self-heal, git deploy and git rollback timings
.\scripts\show-credentials.ps1       # Argo CD admin password to the clipboard
```

Host ports: 31000 checkout, 31001 Grafana, 31002 Argo CD, 31003 Prometheus. After Argo CD is installed, a git push is the deployment; `deploy-kind.ps1` refuses to run unless forced.

## Repository layout

| Path | Contents |
|---|---|
| `services/` | The two FastAPI services, Dockerfiles and pytest suites. |
| `deploy/helm/` | The generic chart and per-service values. |
| `deploy/argocd/` | Argo CD install (pinned v3.4.5) and the app-of-apps. |
| `deploy/monitoring/` | Prometheus, Grafana, dashboards, SLO rules and rule tests. |
| `deploy/metrics-server/` | Vendored metrics-server for the HPA. |
| `load-tests/` | The k6 script. |
| `scripts/` | Everything above, as PowerShell. |
| `docs/` | SLOs, runbooks, RCA, GitOps, load testing, security and the measured results. |
| `.github/` | CI workflow and Dependabot. |

CI jobs: `lint`, `test`, `image`, `chart`, `monitoring`, `load-test-script`, `config-scan`, `secret-scan`, `deploy-test`, `promote`.

## Honest limits

- A single local cluster: no multi-node failure, no real network, no cloud provider, no Terraform.
- Alerts are visible in Prometheus and Grafana but are not routed anywhere (no Alertmanager).
- State is in memory, so a pod restart loses orders and stock. A shared store is the real fix.
- Burn-rate windows are scaled down for the drill; production windows are 5m+1h and 30m+6h.
- Argo CD runs over plain HTTP with its generated admin account.
- The load test found a limit I did not explain. At a 300 req/s target checkout failed its SLOs even with all 6 pods running, yet those pods used only about 200% of their 100m CPU request (roughly 0.2 CPU each, against a 0.5 CPU limit), so checkout CPU alone does not explain it. Candidates, unproven: the single inventory replica, or k6, kind and Docker networking all sharing one machine. I did not find the bottleneck.

## What I would do next

Provision the cluster with Terraform on a managed Kubernetes service, add Alertmanager routing, NetworkPolicies and image signing with cosign, and move state into a real datastore.