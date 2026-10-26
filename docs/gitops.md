# GitOps with Argo CD

**A git push is the deployment.** Nobody runs `helm upgrade` or `kubectl apply` against the cluster; Argo CD watches the repo and makes the cluster match it.

## The flow

```text
git push (code)
  -> CI: lint, tests, build + Trivy scan + push images tagged with the commit sha
  -> CI: deploy those images to a throwaway kind cluster, smoke test, outage drill, short load test
  -> CI "promote" job: commits the new image tag into deploy/helm/values/*.yaml   (this replaced promote-images.ps1)
  -> Argo CD sees the new commit (polls every 30 s here) and rolls the Deployments
```

Images are only promoted after the throwaway-cluster test passes, so a broken build never reaches the values files.

## What lives where

| Path | Purpose |
|---|---|
| `deploy/argocd/kustomization.yaml` | Argo CD itself: upstream manifest pinned to v3.4.5 plus local changes (NodePort 31002, plain HTTP, 30 s git poll, annotation tracking, dex and notifications scaled to 0). |
| `deploy/argocd/root-app.yaml` | "App of apps". The only Argo object applied by hand. |
| `deploy/argocd/apps/*.yaml` | One Application per thing to deploy: `inventory`, `checkout` (Helm chart + values file) and `monitoring` (kustomize). Adding a service is adding a file here. |
| `scripts/install-argocd.ps1` | Bootstrap: install Argo CD, apply the root app, wait until everything is Synced and Healthy. |
| `scripts/gitops-drill.ps1` | Proves self-healing and git-only deploy/rollback; writes `docs/gitops-drill-results.md`. |

## Settings and why

- **Automated sync with prune and selfHeal.** Prune deletes what was removed from git; selfHeal undoes hand edits (drill 1 measures it). Both are what make git the single source of truth.
- **Annotation resource tracking.** The Helm chart uses `app.kubernetes.io/instance` in its selectors. Argo's default label tracking would overwrite that label, so tracking uses an annotation instead.
- **Rollback is `git revert`.** It leaves a record of who undid what and why, and it goes through the same path as any other change.
- **The HPA owns the replica count.** When autoscaling is enabled the Deployment has no `replicas` field, so Argo does not fight the autoscaler.
- **Secrets stay out of git.** The Grafana admin password is created by `deploy-monitoring.ps1` into a Kubernetes Secret and Argo does not manage it. The Argo admin password is the generated `argocd-initial-admin-secret`.

## Day-to-day rules

- The CI promote job pushes a commit to `main` after each green build. **Run `git pull --rebase` before your next `git push`**, otherwise the push is rejected.
- `deploy-kind.ps1` refuses to run on an Argo-managed cluster (self-heal would undo it within seconds). CI uses it on its own throwaway cluster, where Argo is not installed. `-Force` overrides.
- Drill and docs commits that must not trigger CI carry `[skip ci]`.

## Limits of this setup

- Argo CD runs in the same single-node cluster it manages, with a generated local password and no SSO or RBAC. Fine for a demo, not a production control plane.
- Argo reads the public GitHub repo over the internet. A private repo would need a deploy key or token added to Argo.
- One environment. Staging and production would be separate values files (or overlays) with their own Applications and a promotion step between them.
- CI does not install Argo CD; it validates the Argo manifests with kubeconform and tests the images on a plain Helm deploy. The Argo path is exercised locally by the drill.
- Image-tag bumps are plain commits by a bot. Argo CD Image Updater or a PR-based promotion would add review before production.