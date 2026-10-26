# GitOps drill results

Run on 2026-10-26 14:09 against the local kind cluster. Argo CD checks git every 30 s here (the default is 3 minutes), so these times include up to 30 s of waiting for that poll.

| Drill | What happened | Time |
|---|---|---|
| Drift | `kubectl scale deploy/inventory --replicas=3` by hand; Argo CD (selfHeal) restored 1 replica | 0.8 s |
| Deploy by git | Pushed `INVENTORY_TIMEOUT_SECONDS` 2.0 -> 2.5; value reached the Deployment | 25.6 s |
| Deploy by git | Rolling update of checkout finished | 34.5 s after the push |
| Rollback by git | `git revert` pushed; value back to 2.0 | 53.1 s |
| Rollback by git | Rolling update finished | 61.9 s after the push |

Final state of the checkout application: **Synced/Healthy**.

Nothing was applied with kubectl or helm during drills 2a and 2b: the only inputs were two commits and two pushes. The drill commits are tagged `[skip ci]`, so CI did not run for them.
