# Security controls

What is checked, where, and what it found. Everything here runs in CI or is enforced by the cluster; nothing depends on someone remembering.

| Control | Where | What it does |
|---|---|---|
| Image vulnerability scan | CI `image` job (Trivy) | Fails the build on fixable HIGH or CRITICAL CVEs in the built image before it is pushed. Its first run caught three HIGH CVEs in starlette, fixed by upgrading the pinned dependencies. |
| Misconfiguration scan | CI `config-scan` job (Trivy) | Scans the rendered Helm chart for both services, the monitoring and metrics-server manifests, and the Dockerfiles. HIGH or CRITICAL findings fail the build. Its first run found two HIGH findings, both fixed: Grafana ran with a writable root filesystem (now read-only with a `/tmp` emptyDir), and the vendored metrics-server manifest had no pod-level security context (added through the kustomize patch). |
| Secret scan | CI `secret-scan` job (gitleaks) | Scans the whole git history, not only the latest commit. |
| Pod Security Admission | `platform` namespace | `enforce: restricted`. The cluster rejects any pod that runs as root, is privileged, can escalate privileges, keeps default capabilities or has no seccomp profile. Argo CD sets the label (`managedNamespaceMetadata`); the CI test cluster sets it too, so a non-compliant chart fails the deploy test before it can be promoted. |
| Pod hardening | Helm chart | Non-root user, read-only root filesystem, all capabilities dropped, no privilege escalation, seccomp `RuntimeDefault`, no service account token mounted, CPU and memory limits, `/tmp` as an emptyDir. |
| Credentials | `scripts/show-credentials.ps1` | The Argo CD and Grafana admin passwords are generated per cluster, exist only in Kubernetes Secrets, are never written to git and are copied to the clipboard instead of printed. |
| Dependency updates | `.github/dependabot.yml` | Weekly update pull requests for GitHub Actions, Python dependencies and base images, so pinned versions do not rot. |

## Not covered (and why that is fine here)

- **Secrets are base64 in etcd, not encrypted at rest, and there is no external secret manager.** A real cluster would use Vault or a cloud secret manager with the External Secrets Operator.
- **No NetworkPolicies are enforced between the services.** kind's default network plugin may not enforce them, so adding the objects would look like protection that is not there.
- **Images are not signed and there is no SBOM.** Cosign signing and an admission policy that only runs signed images would be the next step.
- **Third-party manifests are not scanned.** The upstream Argo CD install manifest is pinned by version but not scanned; it is somebody else's configuration.
- **Argo CD runs over plain HTTP with the generated admin account**, acceptable for a laptop cluster only.
- **Terraform is not used.** The only infrastructure here is a local kind cluster; managing it with Terraform would add a tool without adding a control.