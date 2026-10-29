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

## Run-to-run variance: four runs of the same 120 req/s test

| | Oct 26 | Oct 29 #1 | Oct 29 #2 | Oct 29 #3 |
|---|---|---|---|---|
| Result | PASS | FAIL | PASS | FAIL |
| Redeployed during the run | no | yes (about t=157 s) | yes (about t=190 s, estimated) | no |
| Failed requests (SLO < 0.5%) | 0.00% | 0.00% (2 of 20,531) | 0.00% (0 of 20,550) | 0.00% (0 of 20,505) |
| p95 (SLO < 500 ms) | 7.26 ms | 40.4 ms | 45.6 ms | 44.7 ms |
| p99 / max | 10.5 ms / 93 ms | 168 ms / 860 ms | 216 ms / 485 ms | 649 ms / 1.41 s |
| Dropped iterations (limit 0) | 0 | 19 | 0 | 45 |
| Peak pods | 5 | 6 | 6 | 6 |

Reports: [Oct 26](load-test-results.md), [#1](load-test-results-rerun-2026-10-29.md), [#2](load-test-results-2026-10-29-rerun2.md), [#3](load-test-results-2026-10-29-clean.md).

What the data supports:
- Both real SLOs (errors and p95) held in all four runs, with a wide margin.
- The only threshold that ever tripped is `dropped_iterations`, the check that k6 kept up. It measures the load generator and the laptop it shares with the cluster, not checkout.
- Run #3 had no redeployment and still failed, so rollouts do not explain the failures. In run #1 a stall of about 20 s (CPU fell from 202% to 3%) and the only two failed requests coincided with a rollout, but run #2 had a rollout too and was clean.

What it does not show:
- Where the 0.5-1.4 s latency spikes on Oct 29 come from. They were absent on Oct 26. Nothing in these runs separates the candidates (the autoscaler adding pods, Docker Desktop networking, other load on the laptop).

Likely mechanism for the drops, not proven: the script preallocated 50 virtual users. At 120 req/s a stall of half a second puts about 60 requests in flight, so k6 has to start more users while iterations are already due, and iterations it cannot start in time are counted as dropped (peak virtual users were 67 in run #1 and 91 in run #3, well below the cap of 500).

Change made: `preAllocatedVUs` is now 200. The thresholds are unchanged. The next clean run will show whether the drops disappear; its result will be added here either way. A first attempt with 200 preallocated users ([report](load-test-results-2026-10-29-prealloc200-rollout.md)) was disturbed by a rollout during the run and failed, so it does not answer the question. Its numbers: 18 dropped iterations, 0.15% failed requests, p95 36.8 ms, p99 1.39 s, max 11.3 s (longest iteration 30 s). Both SLOs still held, but it has the worst tail of any run, so a rollout while 6 pods are serving load can hurt; run #2 also had a rollout and was clean, so the effect varies between runs. Possible follow-up, untested: check the rollout settings (surge and unavailable limits, graceful shutdown, readiness) under load.

First clean run with 200 preallocated users ([report](load-test-results-2026-10-29-prealloc200.md)), no redeployment during the run: PASS. 0 failed requests, 0 dropped iterations, p95 15.7 ms, p99 38.5 ms, max 167 ms, peak 6 pods.

What this does not show: that preallocating more users fixed anything. The worst latency in this run was only 167 ms, so the 0.5-1.4 s spikes that went with the dropped iterations on earlier Oct 29 runs did not occur, and a run without spikes passes with 50 users or with 200. Settling it would take more runs under conditions that produce spikes, and I could not make them happen on demand, so the explanation stays unproven.

Rule from this: after any push, wait for CI's promote commit and Argo CD to finish before running a load test or a drill. `load-test.ps1` now compares the pod templates before and after the run and says so in the verdict if either service was redeployed. It also waits (up to 7 minutes) until CI's promote commit is deployed before it starts; `-SkipSettleCheck` turns that off.