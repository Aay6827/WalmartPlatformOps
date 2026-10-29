# Load testing and autoscaling

Question this answers: **does checkout keep its SLOs when traffic goes from 10 to 120 requests/s, and does the autoscaler add capacity in time?**

## How to run

```powershell
.\scripts\install-metrics-server.ps1   # once per cluster: gives the HPA CPU numbers
.\scripts\deploy-kind.ps1              # applies the HPA (autoscaling is enabled in deploy/helm/values/checkout.yaml)
.\scripts\load-test.ps1                # about 4.5 minutes of load, then watches the scale-down
```

The script runs `load-tests/checkout.js` with k6 (local install, or the `grafana/k6` image through Docker), samples the HPA every 10 s, and writes `docs/load-test-results.md`. Watch it live on the Grafana dashboard **Platform > Checkout scaling and load** (http://localhost:31001).

## Test design

- **Open model.** k6 uses `ramping-arrival-rate`: requests arrive at a fixed rate whether or not checkout keeps up. A closed-loop test (a fixed number of workers waiting for each reply) slows itself down when the service slows down and hides the problem; the first SLO drill had exactly that weakness.
- **Profile.** 10 req/s for 30 s, ramp to 120 req/s over 60 s, hold 120 s, back to 10 req/s for 30 s. Override with `-PeakRps`, `-Hold` and so on.
- **Thresholds are the SLOs** from `docs/slo.md`: failed requests below 0.5%, p95 below 500 ms. A third threshold, no dropped iterations, checks that k6 itself could generate the load; if it fails the numbers are not trustworthy.
- **Only 201 counts as success**, and the response body must contain `CONFIRMED`. Stock is sized (`STOCK_PER_SKU`) so orders never run out and turn into 409s.

## Autoscaling settings (checkout)

| Setting | Value | Why |
|---|---|---|
| CPU request / limit | 100m / 500m | The HPA percentage is relative to the request, so the request has to be realistic. |
| Target | 70% of the request | Leaves headroom while new pods start. |
| Replicas | min 2, max 6 | Min 2 keeps one pod serving during a rollout or node drain. Max 6 caps how far a bad metric or a traffic spike can grow the deployment. |
| Scale up | +2 pods or +100% every 15 s, whichever is larger, no stabilization wait | A spike hurts users now. |
| Scale down | 1 pod per 30 s, after 60 s below target (chart default is 300 s) | Avoids flapping. 60 s is shortened for the local demo; production would keep the 300 s default. |

Inventory does **not** autoscale: it keeps stock in memory, so a second replica would hold a different copy. It is therefore the first thing that saturates, and the dashboard shows its CPU against its limit.

## Reading a result

- Replica count rising before CPU stays above the target for long means the HPA reacts in time; latency climbing before replicas rise means it reacts too late (raise the request/limit headroom, lower the target, or pre-scale).
- `dropped_iterations` above zero with low service CPU means the load generator, not checkout, was the bottleneck.
- CPU of one pod near its 0.5 limit with max replicas reached means the ceiling for this configuration has been found.

## Limits of this setup

Everything (kind, services, Prometheus, Grafana, k6) shares one laptop, so absolute throughput figures are not production numbers. What carries over is the method: SLO-derived thresholds, an open-model generator, and a recorded autoscaler timeline.

## Finding the limit (300 req/s target)

Same script and thresholds, `.\scripts\load-test.ps1 -PeakRps 300 -ReportPath docs/load-test-results-300rps.md`. Result: **FAIL**. Full numbers are in [load-test-results-300rps.md](load-test-results-300rps.md).

| | 120 req/s target | 300 req/s target |
|---|---|---|
| Result | PASS | FAIL |
| Requests completed | 20,550 | 30,936 |
| Dropped iterations | 0 | 19,314 (k6 reached its 500 VU cap) |
| p95 latency (SLO 500 ms) | 7.26 ms | 5.1 s |
| Failed requests | 0.00% | 0.08% (27, connection EOF) |
| Pods | 2 to 5 | reached the limit of 6 at t=112 s |

What the data supports: the autoscaler did its job and ran out of pods. Under load the 6 checkout pods sat at about 200% of their CPU request.

What it does not support: a cause. 200% of a 100m request is about 0.2 CPU per pod, well under the 0.5 CPU limit, so the checkout pods were not CPU-throttled. The unproven candidates are the single inventory replica (every checkout calls it) and the one machine running k6, kind, Docker networking and the monitoring stack together.

To find out, re-run at about 200 req/s and, in a second window, watch `kubectl top pods -n platform` (is inventory the busy pod?) and the inventory call duration in Grafana.

## Run-to-run variance: the same test twice

| | Oct 26 | Oct 29 rerun |
|---|---|---|
| Result | PASS | FAIL (only `dropped_iterations`) |
| Failed requests (SLO < 0.5%) | 0.00% | 0.00% (2 of 20,531, connection EOF) |
| p95 / p99 / max | 7.26 ms / 10.5 ms / 93 ms | 40.4 ms / 168 ms / 860 ms |
| Dropped iterations (limit 0) | 0 | 19 |
| Peak pods | 5 | 6 |

Reports: [Oct 26](load-test-results.md), [Oct 29](load-test-results-rerun-2026-10-29.md).

What the evidence shows: roughly 157 s into the rerun, the autoscaler timeline shows CPU falling from 202% to 3% for about 20 s (traffic stalled), and k6 logged its two connection EOFs at that time. `kubectl get events` shows both checkout pods replaced and the inventory ReplicaSet scaled down at the same moment, running a new image tag. The cause is the CI promote step: a push made shortly before the test produced a new image, CI committed the new tag, and Argo CD rolled it out in the middle of the run.

What it does not show: how a clean 120 req/s run behaves today, because this one was disturbed. Accidentally, it does show that a rolling deploy of both services under about 100 req/s cost 2 failed requests in 20,531.

Rule from this: after any push, wait for CI's promote commit and Argo CD to finish before running a load test or a drill. `load-test.ps1` now compares the pod templates before and after the run and says so in the verdict if either service was redeployed.