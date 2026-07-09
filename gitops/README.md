# Configuration as code (GitOps)

How a customer authors Agent Shield configuration **in GitHub** and has approved changes
applied to their cluster — without cluster credentials ever leaving their boundary.

## The model

Two configuration layers, one workflow:

| Layer | What | Applied by |
|-------|------|-----------|
| **Deployment config** | Helm values, profile choice, image tag, replicas | Flux (or ArgoCD) reconciling a `HelmRelease` |
| **Governance config** | Policies, egress destinations, trusted code hashes, IdP settings | `config-sync` (roadmap — see below) through the admin-token-guarded management APIs |

The workflow for both is identical from the author's seat:

```
edit file on a branch ──> pull request ──> CODEOWNERS review ──> merge to main ──> applied
```

**Merge to a protected branch IS the deployment approval.** Branch protection + CODEOWNERS
on `governance/**` gives you named human approvers on every governance change, enforced by
GitHub, with full history.

## Pull, not push (why)

The in-cluster GitOps agent (Flux) **pulls** from the Git repo over outbound HTTPS:

- **No cluster credentials in GitHub.** A push pipeline (Actions running `helm upgrade`)
  needs cluster-admin creds stored as repo secrets and network reach to the API server —
  both are findings in a hardened-environment review. Pull needs neither.
- **Works with a private EKS endpoint** and inside restricted networks (only outbound 443
  to your GitHub — github.com or GHES — is required).
- **Drift reverts automatically.** Manual `kubectl edit`s are reconciled back to the
  approved state — itself a governance property.

Push-based CI is still possible for dev clusters; this template doesn't preclude it.

## Getting started

1. Copy `config-repo-template/` into a new private repo (e.g. `acme/agent-shield-config`).
2. Vendor the chart: copy `helm/agent-shield` into `charts/agent-shield` (or point
   Flux at an OCI chart registry if we've published one to you).
3. Protect `main`: require PR review; add `CODEOWNERS` entries for `governance/**`.
4. Bootstrap Flux on the cluster (`flux bootstrap github ...` — see
   `config-repo-template/README.md`), pointed at `clusters/prod`.
5. Author config via PRs from then on.

ArgoCD works identically (an `Application` instead of a `HelmRelease`); we default the
template to Flux because it's lighter to operate and has no UI to accredit.

## Governance config (`governance/`) — status

The `governance/` directory in the template holds the **declarative desired state** for
policies, destinations, and IdP settings. Deployment-layer reconciliation (everything above)
works today. The `config-sync` reconciler that applies `governance/**` through the
management APIs — idempotently, stamped with the git commit SHA, every change landing as an
audited event in the ledger — is specced and on the roadmap
(`G8RV2_CONFIG_SYNC_BRIEF`). Until it ships, treat `governance/` as the reviewed source of
truth and apply via the documented admin CLI/API calls.
