# Registry write authentication

Deployment contract for the C05 registry's workload write auth. It
mirrors the C01 audit writer-token design (see `docs/audit-writer-auth.md`).

## The hole

The registry's workload write paths accepted **any** caller with network reach:

- `POST /v1/agents/enroll` — anyone could enroll a fake agent (shadow-agent spoofing, OWASP A01)
- `POST /v1/discovery/observations` — anyone could inject or drown out discovery observations
- `POST /v1/discovery/reconcile` — anyone could trigger reconciliation
- `POST /v1/agents/{id}/heartbeat` — anyone could forge liveness for another tenant's agent
- `POST /v1/agents/{id}/attest` — anyone could push attestation updates

The operator lifecycle mutations (approve/suspend/revoke, capabilities/attributes PATCH, group
mutations) were **already** gated by `admin_guard` (`X-Admin-Token` == `GF_ADMIN_TOKEN`,
fail-closed 503 when unset) and are unchanged.

## The control: enforced-*when-configured*

A shared writer token, `GF_REGISTRY_WRITER_TOKEN`, is presented by every producer on the
`X-Registry-Token` request header (constant-time compare; wrong/missing ⇒ **403**).

| `GF_REGISTRY_WRITER_TOKEN` on C05 | Behaviour of the write paths |
| --- | --- |
| **unset** | **OPEN** — dev convenience only; the production boot guard forbids this state. |
| **set** | `X-Registry-Token` must equal it. Enroll **also** accepts `X-Admin-Token` == `GF_ADMIN_TOKEN` (operator/bootstrap enrollment). |

## The production boot guard — fail-safe by omission

`assert_registry_writer_auth_configured()` runs in the app lifespan. If the token is unset, boot
is allowed **only** when `REGISTRY_ENV` is an explicit dev value (`development`/`dev`/`test`/
`local`). Any other value — and, crucially, `REGISTRY_ENV` being *unset* — refuses to boot, so a
prod deploy that forgets the token crash-loops instead of silently running an open enrollment
surface. `REQUIRE_AUTH=1` forces the token even in dev.

`scripts/ci/security_preflight.sh` additionally fails a `GF_ENV=production` deploy when
`GF_REGISTRY_WRITER_TOKEN` is missing/weak or `REGISTRY_ENV` is a dev value.

## Rollout

1. Generate a high-entropy secret: `openssl rand -hex 32`. Distinct from `GF_ADMIN_TOKEN` and
   `GF_AUDIT_WRITER_TOKEN`.
2. Set the **same value** on C05 (`GF_REGISTRY_WRITER_TOKEN`) and every producer that calls the
   write paths — any customer workload that enrolls agents or posts discovery observations. (The
   PEP, the compliance service, and the management-api do **not** call these paths — compliance and
   management-api only read, or use the already-admin-gated mutations; the registry's own
   telemetry consumer ingests in-process, not over HTTP.)
3. Set `REGISTRY_ENV=production` on C05 so the boot guard is explicit about posture (the shipped
   Helm chart already does this).
4. Rotation: dual-run — update producers to the new token first, then flip C05.
