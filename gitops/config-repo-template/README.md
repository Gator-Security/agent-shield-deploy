# agent-shield-config (template)

Your Agent Shield configuration repo. Every change lands via a reviewed pull request; the
in-cluster Flux agent pulls approved state from `main` and reconciles the cluster to it.

## Layout

```
charts/agent-shield/       # vendored copy of the Agent Shield chart (or use an OCI source)
clusters/
  prod/
    agent-shield/
      helmrelease.yaml      # Flux HelmRelease: chart + profile + your values
      values.yaml           # your overrides (image tag, replicas, ingress host...)
governance/                 # DECLARATIVE governance config (PR-reviewed source of truth)
  policies/                 # policy source, one file per policy
  destinations.yaml         # egress destinations allowlist
  idp.yaml                  # OIDC IdP settings (issuer, client id, claim names — no secrets)
CODEOWNERS                  # named approvers; governance/** requires security-team review
```

## Bootstrap (once per cluster)

```bash
flux bootstrap github \
  --owner=<org> --repository=agent-shield-config \
  --branch=main --path=clusters/prod --personal=false
```

This installs Flux into the cluster and commits its own manifests under
`clusters/prod/flux-system/`. From then on the cluster follows `main`.

For GitHub Enterprise Server add `--hostname=<ghes-host>`. Air-gapped variants (OCI artifact
sync instead of git) are supported by Flux if outbound HTTPS to GitHub is not allowed.

## Rules

- **Nothing merges to `main` without review.** Branch protection enforces it; CODEOWNERS
  routes `governance/**` to the right approvers.
- **No secrets in this repo, ever.** Secrets live in the cluster Secret (`gf-secrets`) or
  your secret manager via External Secrets. `idp.yaml` carries identifiers, not credentials.
- **Roll back by reverting the commit.** The cluster follows `main`; `git revert` is the
  rollback mechanism, with the same review gate.
