# Runbook: CheckoutFastBurn (page)

**What it means.** More than about 7% of `POST /checkout` requests are failing with 5xx, measured over both the last 1 and 5 minutes. At this rate the whole monthly error budget (0.5%) is gone in roughly two days, so someone acts now.

**Look first.** Grafana dashboard *Platform > Checkout SLO*: burn rate, requests by status, and the *Inventory dependency* tile.

## Triage

1. **Is inventory down?** If *Inventory dependency* shows DOWN, or `InventoryDependencyDown` is also firing, this is almost certainly the cause.
   ```
   kubectl -n platform get pods -l app.kubernetes.io/name=inventory
   kubectl -n platform describe pod -l app.kubernetes.io/name=inventory
   kubectl -n platform logs deploy/inventory --tail=100
   ```
   Checkout deliberately returns **503** (not a hang) and stays Ready, so users see fast failures and checkout recovers by itself once inventory is back.
2. **Did something just change?** `helm -n platform history checkout` and `helm -n platform history inventory`. If a rollout lines up with the start of the burn, roll it back: `helm -n platform rollback <release> <revision> --wait`.
3. **Is it checkout itself?** Failing with status 500 rather than 503 points at checkout: `kubectl -n platform logs deploy/checkout --tail=100`.
4. **Are pods being scraped?** `PlatformTargetDown` means the data may be incomplete: check http://localhost:31003/targets.

## Mitigate

- Inventory crash-looping: roll back the last inventory release, or `kubectl -n platform rollout restart deploy/inventory`.
  Inventory keeps stock in memory, so a restart resets stock (known limitation, see README).
- Bad checkout release: `helm -n platform rollback checkout`.

## After

Note start/end time and cause, and check how much budget was spent (burn rate x duration). If the cause was a missing alert or a slow page, fix that in `deploy/monitoring/slo.rules.yml`.