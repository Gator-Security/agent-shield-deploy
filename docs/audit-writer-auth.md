# Audit ingest writer authentication + the management-plane trust boundary

This document is the deployment contract for two related hardening controls in the hybrid trust-boundary hardening:

1. **Control-plane write auth** (PDP publish + audit export/checkpoint). Already
   merged; summarized below for context.
2. **Audit ingest writer authentication** (`/v1/audit/events` append +
   `/v1/audit/reconcile`), covered in full here.

It also records the **deferred-but-required** production posture for the management-api's header
trust model (the reason the full C04 session/BFF work is safe to defer).

---

## 1. Audit ingest writer auth

### The hole
C01's ingest endpoints — `POST /v1/audit/events` (append) and `POST /v1/audit/reconcile`
(WAL drain) — accepted **any** caller that could reach them. Anyone with network access to the
audit store could forge governance records or flood the ledger. For a governance product whose
entire value is a trustworthy audit trail, an unauthenticated ledger writer is false assurance.

### The control: enforced-*when-configured*
A shared writer token, `GF_AUDIT_WRITER_TOKEN`, is presented by every producer on the
`X-Audit-Token` request header and checked by C01's `writer_guard`.

The guard is deliberately **not** fail-closed the way the admin guard is:

| `GF_AUDIT_WRITER_TOKEN` on C01 | Behaviour of append / reconcile |
| --- | --- |
| **unset** | **OPEN** — the write is accepted with or without a token. |
| **set** | `X-Audit-Token` must equal it (constant-time compare); missing/wrong ⇒ **403**. |

Why open-when-unset instead of `503`? Append is the **mandatory-audit path**: a governance
event must never be silently dropped. If C01 disabled ingest whenever the token were unset, a
single misconfiguration would silently lose the audit trail — the cardinal sin. So the guard only
*enforces* once a token is configured.

### The production boot guard closes the "open in prod" gap — fail-safe by omission
Because open-when-unset would otherwise be reachable in production, C01 **refuses to boot** unless
the deploy either sets the token or *explicitly* declares itself development:

- `assert_writer_auth_configured()` runs on startup (FastAPI lifespan).
- If `GF_AUDIT_WRITER_TOKEN` is set ⇒ boots (and `writer_guard` enforces it). Otherwise:
- boot is allowed **only** when `AUDIT_STORE_ENV` is set to an explicit dev value
  (`development`/`dev`/`test`/`local`). **Any other value — and, critically, the variable being
  _unset_ — refuses to boot** (`RuntimeError`). `REQUIRE_AUTH=1` forces the token regardless.
- The guard reads the **raw** env (not the `Settings` default), so an *unset* `AUDIT_STORE_ENV` is
  distinguishable from an explicit `development` and is treated as fail-closed.

Net effect: **forgetting to configure fails safe.** A prod deploy that simply omits the config
crash-loops (loud, fail-closed) rather than silently running an anonymous ledger. Open ingest exists
only when an operator *explicitly* marks the deploy development. The shipped Helm chart sets
`AUDIT_STORE_ENV=production` on C01 **and** wires `GF_AUDIT_WRITER_TOKEN` on C01 + every producer.

### What every operator must do in production
1. Generate a high-entropy secret and set `GF_AUDIT_WRITER_TOKEN` to the **same value** on C01
   **and every producer** (below). Deliver it via your secret store, never in plaintext at rest.
2. Set `AUDIT_STORE_ENV=production` (or `REQUIRE_AUTH=1`) on C01 so the boot guard is active.
3. Rotate by dual-running: set the new token on all producers first, then flip C01. (A brief
   window where a producer sends the old token ⇒ that producer's events buffer to its WAL and
   reconcile once the token matches — no loss, by the mandatory-audit guarantee.)

### Producers wired to send `X-Audit-Token`
All are gated on `GF_AUDIT_WRITER_TOKEN` being set in **their** environment (unset ⇒ header
omitted, matching the open-ingest dev path):

| Producer | Path(s) | Reads |
| --- | --- | --- |
| PEP gateway | append + reconcile (`_ingest_headers`) | `GF_AUDIT_WRITER_TOKEN` |
| PDP | append (`Emit`) | `GF_AUDIT_WRITER_TOKEN` |
| Registry | append | `GF_AUDIT_WRITER_TOKEN` |
| Management API | append — `emitAudit` (notifications/incidents) **and** the fail-closed HITL approval-decision append | `GF_AUDIT_WRITER_TOKEN` → `Server.AuditWriterToken` |
| Customer SDK (Python) | append + async + reconcile (`_ingest_headers`) | `GF_AUDIT_WRITER_TOKEN` |
| Customer SDK (TypeScript) | append + reconcile (`ingestHeaders`) | `process.env.GF_AUDIT_WRITER_TOKEN` |
| MCP server | append (`ToolCallAuditor.record`) | `GF_AUDIT_WRITER_TOKEN` |

> **Fail-closed producer (management-api HITL approval):** the human-approval decision append is
> fail-closed — a non-2xx blocks the approval (no gate cleared without a durable record). It
> therefore MUST carry the writer token, or a token-configured C01 would 403 it and brick the
> approval flow. It does.

> **Drive-by fix:** the MCP server's tool-call audit was sending **no** `X-Tenant-ID`
> header, so C01 rejected every record with a `400` — the tool-call audit trail was silently
> empty. That is fixed here (tenant scope header added) alongside the writer token.

### Failure semantics (the mandatory-audit guarantee preserved end to end)
- PEP / SDK: a `403` (or any non-2xx) buffers the event to the locally-chained+signed WAL and
  retries via reconcile — never dropped.
- Registry: audit is fail-open by design (a C01 problem must not block a registry mutation that
  already committed); a `403` is counted + logged **loudly** as a rejection, never silent.
- PDP / management-api: emit is best-effort off the hot path; a `403` is logged. In production the
  token is configured everywhere (contract above), so `403` indicates a real misconfiguration to
  fix, not steady-state.

---

## 2. Management-plane header trust (the hybrid boundary — deferred, documented)

The management-api derives the caller's roles and tenant from **`X-GF-Roles` / `X-GF-Tenant`**
request headers. This is trustworthy **only** if those headers are set by an authenticating layer
the client cannot reach around. The full session/identity-broker work (C04) is **deferred**; the
safe interim contract is:

**The management-api MUST be deployed behind a Backend-for-Frontend (BFF) / authenticating reverse
proxy that:**

1. Authenticates the human/service caller (SSO/OIDC), and
2. **Strips any client-supplied `X-GF-*` headers** and re-sets `X-GF-Roles` / `X-GF-Tenant` (and
   `X-GF-User`) from the verified session — so a caller can never assert its own roles/tenant, and
3. Is the **only** network path to the management-api (the management-api is not exposed directly).

This is defense-in-depth, not the last line: the crown-jewel *enforcement* plane (PDP decisions,
C01 ledger, PEP) does **not** trust these headers — PDP publish/activate and the audit ingest are
now independently authenticated (admin token, writer token), and tenant scoping on
the enforcement path comes from PDP-side stores, never a request body. The header-trust model
only governs the management/console plane; compromising it cannot forge a decision or a ledger
entry, only misattribute a console action — which the BFF requirement above closes.

> Until a deployment satisfies the BFF contract, treat the management-api as reachable only from a
> trusted network segment. The remaining full-fidelity fix (per-user subject propagation + session
> broker) is tracked as C04 / `X-GF-Subject`.

---

## 3. Related controls (context)

- **Control-plane write auth** — `POST /v1/policies` (PDP publish) and C01 export/checkpoint now require the admin
  token (`X-Admin-Token` == `GF_ADMIN_TOKEN`; unset ⇒ `503`, mismatch ⇒ `403`). Policy `validate`
  stays ungated (read-only).
- **`GF_ADMIN_TOKEN`** (privileged control-plane actions) and **`GF_AUDIT_WRITER_TOKEN`** (audit
  ingest) are **distinct** secrets with distinct blast radii — do not reuse one for the other.
