# Configuration profiles

Opinionated values overlays for the umbrella chart. Each profile is a plain Helm values file
layered on top of the chart defaults:

```bash
helm upgrade --install agent-shield ./agent-shield \
  -f agent-shield/profiles/baseline.yaml \
  [-f agent-shield/profiles/fedgov-cac.yaml] \
  --namespace agent-shield
```

The Terraform EKS module selects one via `config_profile` (default `baseline`).

| Profile | Use it when |
|---------|-------------|
| `baseline.yaml` | Every install. The fail-closed checklist from `docs/deployment-guide.md` expressed as enforceable config instead of prose. |
| `fedgov-cac.yaml` | Government / regulated customers authenticating humans with CAC/PIV smartcards through a CAC-capable OIDC IdP. Self-contained (includes the baseline settings) — see `docs/cac-piv-integration.md` for the end-to-end setup. |

## What a profile can and cannot enforce

Profiles set chart values only. Three checklist items live **outside** the chart and still
need operator attention:

- **`ALLOW_DEV_SEED` and `REGISTRY_SIGSTORE_TEST_*` must be UNSET.** The chart never sets
  them; a profile cannot "unset harder". Anything that re-adds them (a kustomize patch, a
  manual `kubectl set env`) reopens dev backdoors.
- **The egress-firewall chokepoint** is deployed alongside
  workloads, not by this chart. Where you run it: `EGRESS_FAIL_OPEN=false` and
  `EGRESS_PDP_URL` set — see `docs/egress-chokepoint.md`.
- **Edge TLS** (ACM cert on the ALB / your ingress controller) is infrastructure, not chart
  config. The Terraform module takes `acm_certificate_arn`.

## Authoring rules for new profiles

- Only reference env vars that exist in `docs/configuration-reference.md` — never
  invent config keys.
- Secrets never go in a profile. Map them through `secretEnv`/`optionalSecretEnv` to keys in
  the pre-created Secret (`existingSecret`), and document the key in
  `helm/agent-shield/secrets.env.example`.
- Keep profiles self-contained (don't require stacking N files in the right order) and
  comment every override with *why*.
