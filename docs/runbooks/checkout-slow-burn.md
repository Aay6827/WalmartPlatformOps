# Runbook: CheckoutSlowBurn (ticket)

**What it means.** The error rate is above 6x the budget over both 5 and 30 minutes. Nothing is on fire, but at this pace the month's budget will run out. Handle it during working hours.

**Look first.** *Checkout SLO* dashboard, burn-rate panel: is it a steady trickle or a spike that has already ended? A spike that ended keeps this alert firing until the 30-minute window clears; that is expected.

## Triage

1. Break the errors down by status in the *Checkout requests/s by status* panel. Steady 500s mean a bug; 503s mean a dependency problem (inventory).
2. Compare with recent releases: `helm -n platform history checkout`.
3. Check resource pressure: `kubectl -n platform top pods` and restarts in `kubectl -n platform get pods`.

## Resolve

Fix the cause, or roll back (`helm -n platform rollback <release> <revision> --wait`). Close the ticket once the 30-minute burn rate is back under 1.