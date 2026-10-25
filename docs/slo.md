# Service level objectives

| SLO | Target | SLI (what is measured) |
|---|---|---|
| Checkout availability | 99.5% | share of `POST /checkout` that does **not** return 5xx |
| Checkout latency | 95% under 500 ms | share of `POST /checkout` completing within 500 ms |

4xx responses (unknown SKU, insufficient stock) are the client's outcome and do not count against availability.

**Error budget:** 0.5% of requests. **Burn rate** = observed error ratio / 0.005, so a burn rate of 1 spends the budget exactly over the SLO window.

| Alert | Fires when | Severity |
|---|---|---|
| CheckoutFastBurn | burn rate > 14.4 on both the 1m and 5m windows | page |
| CheckoutSlowBurn | burn rate > 6 on both the 5m and 30m windows | ticket |
| CheckoutLatencySLO | more than 5% of requests slower than 500 ms for 1m | ticket |
| InventoryDependencyDown | a checkout pod's calls to inventory are failing | page |
| PlatformTargetDown | a pod stopped being scraped | ticket |

All burn-rate alerts also require more than 0.2 requests/s, so a few errors on idle traffic never page.

**Windows are scaled down for the local drill.** Production practice is 5m+1h (page, 14.4x) and 30m+6h (ticket, 6x). The rules are identical; only the ranges differ.

The rules are unit-tested with `promtool test rules` (healthy traffic, total outage, 4xx-only traffic, trickle traffic, dependency down), and the same tests run in CI.

Measured behaviour from a real outage drill: see [slo-drill-results.md](slo-drill-results.md) once `scripts/slo-drill.ps1` has been run.