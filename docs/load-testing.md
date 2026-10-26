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