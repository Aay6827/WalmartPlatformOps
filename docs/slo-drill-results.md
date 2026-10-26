# SLO drill results

Measured on the local kind cluster on 2026-10-26 20:13 (Prometheus scrape and rule evaluation every 5 s).

Scenario: steady checkout traffic for 240 s, inventory scaled to 0 for 150 s, then restored and watched for 120 s. Alert times are seconds after the outage began (resolved: seconds after inventory was restored).

| Alert | Pending | Firing | Resolved |
|---|---|---|---|
| CheckoutFastBurn | 27 s | 41 s | not reached |
| CheckoutSlowBurn | 21 s | 51 s | not reached |
| CheckoutLatencySLO | not reached | not reached | not reached |
| InventoryDependencyDown | 10 s | 27 s | 15 s |
| InventoryAbsent | 21 s | 51 s | 11 s |
| PlatformTargetDown | not reached | not reached | not reached |

Request latency as seen by the client, per phase and HTTP status (seconds):

| Phase | Requests/s (all statuses) | HTTP status | Requests | Median | p95 | Max |
|---|---|---|---|---|---|---|
| healthy | 6.7 | 201 | 1612 | 0.082 | 0.097 | 2.153 |
| outage | 8.7 | 201 | 36 | 0.079 | 0.092 | 0.092 |
| outage | 8.7 | 503 | 1268 | 0.050 | 0.055 | 0.071 |
| recovery | 0.3 | 201 | 54 | 0.089 | 0.105 | 0.106 |
| recovery | 0.3 | 503 | 62 | 0.048 | 0.052 | 0.054 |

Notes: CheckoutSlowBurn uses a 30-minute window, so it can keep firing long after recovery; that is expected.
The burn-rate windows are scaled down for the drill (see deploy/monitoring/slo.rules.yml and docs/slo.md).
