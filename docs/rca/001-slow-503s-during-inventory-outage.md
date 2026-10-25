# RCA-001: checkout 503s were slow during an inventory outage

Found by the SLO drill on 2026-10-25 (local kind cluster). No real users were affected.

## Summary

With inventory scaled to zero under steady traffic, checkout correctly answered 503 and stayed Ready, but each 503 took about a second instead of milliseconds. Request throughput fell from about 6.4/s to about 1.3/s and `CheckoutLatencySLO` fired. A circuit breaker and a 0.5 s connect timeout in checkout fixed it: 503 median 48 ms, p95 53 ms.

## Why it matters

A dependency outage should not make the healthy service slower. If every failing call holds a worker for about a second, capacity drops exactly when the system is degraded, and callers see timeouts instead of fast errors.

## Evidence

Before (first drill, `inventory_call_duration_seconds` and request counts):

- 1,131 checkout-to-inventory calls in total: 1,023 finished in 25 ms or less, 108 took between 1 s and 2.5 s.
- 124 x HTTP 503 in about 113 s of outage, which works out to roughly 0.9 s per request (derived, not measured per request).
- Sparse probe (one request every 8 s, pod already gone): the first request took 2.16 s (the old 2 s timeout), every later one 0.01 to 0.02 s.

After (second drill, client-side latency, seconds):

| Phase | Req/s | Status | Requests | Median | p95 | Max |
|---|---|---|---|---|---|---|
| healthy | 6.4 | 201 | 1546 | 0.083 | 0.105 | 2.116 |
| outage | 8.5 | 503 | 1247 | 0.048 | 0.053 | 0.068 |
| outage | 8.5 | 201 | 34 | 0.083 | 0.104 | 0.109 |
| recovery | 6.7 | 201 | 750 | 0.081 | 0.102 | 0.216 |
| recovery | 6.7 | 503 | 59 | 0.049 | 0.054 | 0.057 |

`CheckoutLatencySLO` did not fire in the second drill. The 201s during the outage are the few seconds before the old pod finished terminating.

## Cause

What is established: connections to a Service with no endpoints were not refused instantly under sustained traffic, so each failing call waited about a second. With sparse traffic they were refused immediately, except the first call after the pod vanished.

What is not established (hypotheses only):

- The 2 s first call fits a pooled keep-alive connection to the dead pod that hangs until the read timeout.
- The roughly 1 s calls under load fit the kernel rate-limiting its ICMP "port unreachable" replies, so most connection attempts fall back to a 1 s SYN retry.

The circuit breaker removed the symptom, so there was nothing left to test these against. Confirming would need a packet capture or `net.ipv4.icmp_ratelimit` on the node. The second drill also had one unexplained 2.1 s healthy request out of 1,546, possibly client-side connection setup.

## Fix

Stop depending on the network to say "no" quickly:

- Circuit breaker in the checkout inventory client: after 3 consecutive failures, calls are refused immediately for 5 s (instant 503), then one probe call is let through; success closes the circuit, failure reopens it. A 4xx from inventory proves it is alive and never counts as a failure.
- Connect timeout 0.5 s (read timeout stays 2 s).
- `inventory_circuit_open` metric and a dashboard tile.

## Other gaps the same drill exposed

1. `PlatformTargetDown` (`up == 0`) never fired when inventory was scaled to zero, because the scrape target simply disappears. Added `InventoryAbsent` (`absent(up{app="inventory"} == 1)`), covered by a promtool unit test.
2. The ticket alert fired before the page alert in the first drill. The drill started with almost no metric history, so the 30 minute window behaved like the 5 minute one. With 4 minutes of healthy history the page alert fires first (49 s vs 55 s).
3. Two of my own claims were wrong and were corrected: the smoke test's "503 in 0.01 s" measured a single request on idle traffic, and the first drill script said "about 10 requests/s" while the real rate was 6.4/s healthy and 1.3/s during the outage. The drill now records the real rate and per-phase latency.

## Follow-ups

- Alert routing: alerts are visible in Prometheus and Grafana, but nothing is sent anywhere yet (no Alertmanager).
- Inventory and checkout orders keep state in memory (single inventory replica); a shared store is the real fix.
- Production-style burn-rate windows (5m+1h, 30m+6h) instead of the drill-scaled ones.