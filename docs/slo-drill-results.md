# SLO drill results

Measured on the local kind cluster on 2026-10-25 14:21 (Prometheus scrape and rule evaluation every 5 s).

Scenario: steady checkout traffic for 240 s, inventory scaled to 0 for 150 s, then restored and watched for 120 s. Alert times are seconds after the outage began (resolved: seconds after inventory was restored).

| Alert | Pending | Firing | Resolved |
|---|---|---|---|
| CheckoutFastBurn | 34 s | 49 s | 75 s |
| CheckoutSlowBurn | 24 s | 55 s | not reached |
| CheckoutLatencySLO | not reached | not reached | not reached |
| InventoryDependencyDown | 14 s | 30 s | 19 s |
| InventoryAbsent | 14 s | 45 s | 19 s |
| PlatformTargetDown | 14 s | not reached | not reached |

Request latency as seen by the client, per phase and HTTP status (seconds):

| Phase | Requests/s (all statuses) | HTTP status | Requests | Median | p95 | Max |
|---|---|---|---|---|---|---|
| healthy | 6.4 | 201 | 1546 | 0.083 | 0.105 | 2.116 |
| outage | 8.5 | 201 | 34 | 0.083 | 0.104 | 0.109 |
| outage | 8.5 | 503 | 1247 | 0.048 | 0.053 | 0.068 |
| recovery | 6.7 | 201 | 750 | 0.081 | 0.102 | 0.216 |
| recovery | 6.7 | 503 | 59 | 0.049 | 0.054 | 0.057 |

Notes: CheckoutSlowBurn uses a 30-minute window, so it can keep firing long after recovery; that is expected.
The burn-rate windows are scaled down for the drill (see deploy/monitoring/slo.rules.yml and docs/slo.md).
