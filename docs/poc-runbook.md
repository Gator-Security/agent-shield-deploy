# Agent Shield POC Runbook — first hour, first week

This is the operating guide for a proof-of-concept of Agent Shield deployed in **your own AWS
account** via the EKS Terraform module (`terraform/eks`). It is written for two readers:
your platform engineer running the install, and the Agent Shield team supporting you.

Throughout, replace:

| Placeholder | Meaning |
|---|---|
| `<REGION>` | your AWS region (e.g. `us-east-2`) |
| `<ACCOUNT_ID>` | your 12-digit AWS account id |
| `<TENANT>` | your tenant UUID for the POC — this runbook uses `11111111-1111-1111-1111-111111111111` |

The Kubernetes namespace is `agent-shield` (Terraform default).

---

## 1. Prerequisites and image mirror

On the workstation running the install:

- Terraform >= 1.6
- `aws` CLI (authenticated against the target account) and `kubectl`
- `python3` with the `cryptography` package (Terraform runs it once to mint the console keypair)
  and the `argon2-cffi` package (for the admin-password hash helper)
- Docker (or podman: `CONTAINER_TOOL=podman`) — for the image mirror

**Step 0 (vendor side — one-time per customer).** Your Agent Shield contact grants your AWS
account read-only pull access to the `agent-shield/*` image repositories in the Agent Shield ECR.
Tell them your 12-digit account id before the install call. The grant covers pull actions only and
is revocable.

**Step 1 (your side).** Mirror the 9 Agent Shield images into your own ECR, so your cluster
pulls from your own registry (the Terraform default):

```bash
scripts/mirror_images.sh <REGION> <ACCOUNT_ID> 0.1.0
```

The script logs in to both registries, creates the `agent-shield/*` repositories in your account
if missing (scan-on-push enabled), mirrors all 9 images (`audit-store`, `pdp`, `registry`,
`egress`, `identity`, `compliance`, `pep`, `management-api`, `ui`) at the given tag, and verifies
each digest. It must end with every service marked `OK`. Re-run it whenever you take a new
release tag.

---

## 2. Install

```bash
cd terraform/eks
cp terraform.tfvars.example terraform.tfvars
```

Generate the bootstrap console-admin password hash (prompts for a password, prints an
`$argon2id$...` hash; the password itself never enters Terraform state or the cluster):

```bash
python3 ../../scripts/make_admin_hash.py
```

Add to `terraform.tfvars` (alongside `region`, node sizing, etc.):

```hcl
bootstrap_admin_email         = "you@yourcompany.com"
bootstrap_admin_password_hash = "$argon2id$v=19$m=65536,t=3,p=4$..."   # from make_admin_hash.py
```

Terraform validates the value starts with `$argon2id$` and the identity service re-validates at
boot — a plaintext-looking value is refused (see troubleshooting). Then:

```bash
terraform init
terraform apply

# point kubectl at the new cluster
$(terraform output -raw configure_kubectl)

# everything Running?
kubectl -n agent-shield get pods

# the console URL (ALB DNS — re-run in a minute if it prints "ALB provisioning")
terraform output console_url
```

One apply creates the VPC, EKS cluster + nodes, RDS Postgres (the audit ledger), the
`gf-secrets` Secret (all tokens generated in-run, never passed through Helm values), the Helm
release, and the public console ALB. Only the console UI is exposed; the management API (:8090)
stays cluster-internal by design — never route it to the public internet.

---

## 3. First login

Open the `console_url` in a browser and sign in with the bootstrap admin **email + password**
from step 2. The login form posts to the console's server-side BFF (`/api/auth/login`), which
authenticates against the in-cluster identity service and sets an httpOnly session cookie; the
browser never talks to the management plane directly.

SSO/OIDC (including CAC/PIV via the `fedgov-cac` configuration profile) is a **mid-POC
milestone, not a day-1 step** — plan it for week 1+ (section 6). Day 1 is email/password with
the bootstrap admin.

---

## 4. Protect the first agent

Work from a terminal with `kubectl` access. Export the tokens Terraform generated:

```bash
NS=agent-shield
export GF_REGISTRY_WRITER_TOKEN=$(kubectl -n $NS get secret gf-secrets -o jsonpath='{.data.GF_REGISTRY_WRITER_TOKEN}' | base64 -d)
export GF_ADMIN_TOKEN=$(kubectl -n $NS get secret gf-secrets -o jsonpath='{.data.GF_ADMIN_TOKEN}' | base64 -d)
TENANT=11111111-1111-1111-1111-111111111111
```

For the curl steps below, port-forward the three services (in separate shells, or `&`):

```bash
kubectl -n $NS port-forward svc/registry 8085:8085
kubectl -n $NS port-forward svc/pdp      8082:8082
kubectl -n $NS port-forward svc/audit    8080:8080
kubectl -n $NS port-forward svc/pep      8083:8083
```

### 4a. Enroll the agent (registry)

Enrollment auth is the `X-Registry-Token` header carrying `GF_REGISTRY_WRITER_TOKEN`
(**not** `Authorization: Bearer` — that header is ignored). Operators may alternatively use
`X-Admin-Token` with `GF_ADMIN_TOKEN`.

First, trust your agent's code hash. Attestation fails closed: a well-formed but unrecognized
sha256 is rejected and the agent is recorded as `revoked`. Add the hash to the allowlist and
restart the registry:

```bash
AGENT_HASH=sha256:$(sha256sum your-agent-bundle.tar.gz | cut -d' ' -f1)
kubectl -n $NS patch secret gf-secrets -p "{\"stringData\":{\"REGISTRY_TRUSTED_CODE_HASHES\":\"$AGENT_HASH\"}}"
kubectl -n $NS rollout restart deploy/registry
```

(Equivalently, set `registry_trusted_code_hashes` in `terraform.tfvars` and re-apply. The
value is a comma-separated sha256 allowlist.)

Then enroll:

```bash
curl -s -X POST http://localhost:8085/v1/agents/enroll \
  -H 'Content-Type: application/json' \
  -H "X-Registry-Token: $GF_REGISTRY_WRITER_TOKEN" \
  -d '{
    "tenant_id": "'$TENANT'",
    "display_name": "billing-support-agent",
    "type": "llm_agent",
    "version": "1.0.0",
    "risk_tier": "medium",
    "capabilities": ["llm_call"],
    "attestation": { "type": "code_hash", "value": "'$AGENT_HASH'" }
  }'
```

A `201` returns the agent record plus `approval_required`. If the agent lands
`pending_approval`, approve it (admin-gated, tenant-scoped):

```bash
curl -s -X POST http://localhost:8085/v1/agents/<AGENT_ID>/approve \
  -H 'Content-Type: application/json' \
  -H "X-Admin-Token: $GF_ADMIN_TOKEN" -H "X-Tenant-Id: $TENANT" \
  -d '{"new_status": "enrolled", "reason": "POC approval", "actor_id": "you@yourcompany.com"}'
```

### 4b. Author and activate the first policy (PDP)

Both calls are admin-gated with `X-Admin-Token`; **activate additionally requires the
`X-Tenant-Id` header** to scope the change. Publish stores an inert draft; activation is the
enforcement change.

```bash
# publish (Cedar source)
curl -s -X POST http://localhost:8082/v1/policies \
  -H 'Content-Type: application/json' -H "X-Admin-Token: $GF_ADMIN_TOKEN" \
  -d '{
    "tenant_id": "'$TENANT'",
    "name": "poc-baseline",
    "layer": "tenant",
    "engine": "cedar",
    "source": "permit(principal, action, resource);"
  }'
# note the "policy_id" in the 201 response, then:

curl -s -X POST http://localhost:8082/v1/policies/<POLICY_ID>/activate \
  -H 'Content-Type: application/json' \
  -H "X-Admin-Token: $GF_ADMIN_TOKEN" -H "X-Tenant-Id: $TENANT" \
  -d '{"tenant_id": "'$TENANT'"}'
```

Until a policy is activated for the tenant, every decision is `DENY` with reason
`NO_APPLICABLE_POLICY` — that is the fail-closed default, not a bug.

### 4c. Wire your agent through the enforcement point (PEP)

Your agent calls the PEP gateway — in-cluster at `http://pep:8083`, or
`http://localhost:8083` via the port-forward above. Two entry points:

- `POST /decide` — decision only (allow/deny + reasons); your code enforces the outcome.
- `POST /proxy` — full enforcement: decision, obligation redaction, governed forwarding to
  `downstream_url`, and output-side governance of the response.

Identify the caller with the `X-GF-Tenant-ID` and `X-GF-Agent-ID` headers (use the `agent_id`
from 4a). Minimal TypeScript, no SDK required — the gateway is plain REST:

```ts
const res = await fetch("http://pep:8083/decide", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "X-GF-Tenant-ID": process.env.GF_TENANT_ID!,   // 11111111-1111-...
    "X-GF-Agent-ID": process.env.GF_AGENT_ID!,     // agent_id from enrollment
  },
  body: JSON.stringify({
    downstream_url: "https://api.openai.com/v1/chat/completions",
    action_type: "egress_http",   // one of: tool_call | egress_http | data_read | state_change | other
    action_hint: "llm_call",
    body: { prompt: "Summarize the Q1 earnings report" },
  }),
});
const { decision, audit_event_id } = await res.json();
if (decision.outcome !== "ALLOW") throw new Error(`blocked: ${decision.reason_code}`);
```

> Note on the published npm SDK: `@g8r-security/agent-shield-sdk` is the client for the
> **hosted Agent Shield Console** (`G8R_CONSOLE_URL` + `G8R_API_KEY` against the Console's
> `/api/sdk/v1/check`). The self-hosted control plane in this runbook does not serve that API —
> for this POC, integrate against the PEP gateway as shown above.

### 4d. Verify the decision landed in the audit ledger

Every PEP/PDP decision is recorded in the tamper-evident audit store. Reads are tenant-scoped
via the `X-Tenant-ID` header (must be the tenant **UUID**):

```bash
curl -s "http://localhost:8080/v1/audit/events?limit=10" -H "X-Tenant-ID: $TENANT"
```

You should see your decision events (with outcomes and reason codes) — the same feed the
console renders. `GET /v1/audit/events/<event_id>/proof` returns a Merkle inclusion proof
against a signed checkpoint if you want to show tamper-evidence during the POC.

---

## 5. Demo scenario: blocking prompt injection

The prompt-injection demo publishes + activates a Cedar policy that denies any governed action
whose prompt trips the PDP's prompt-injection detector, then runs four narrated live decisions
(2 benign → ALLOW, 2 injections → DENY). It needs only the PDP port-forward from section 4 and the
admin token.

Ask your Agent Shield contact for the prompt-injection demo bundle — the demo tooling is not
shipped in this repo. Keep the console open on the decision/audit feed while it runs; each verdict
appears live.

---

## 6. Week 1+ checklist

- **TLS.** Issue an ACM certificate in `<REGION>` for your console domain, set
  `acm_certificate_arn` in `terraform.tfvars`, and `terraform apply`. This turns on HTTPS with
  HTTP→HTTPS redirect on the ALB. HTTP-only is acceptable for a smoke test, never beyond it.
- **Remote Terraform state.** Copy `backend.tf.example` → `backend.tf` (S3 + KMS + DynamoDB
  lock) and `terraform init -migrate-state`. State contains the DB password, tokens, and the
  console signing seed in plaintext — it must live encrypted and access-controlled.
- **Backups.** RDS automated backups are enabled with **7-day retention** by default. For
  production posture set `db_multi_az = true` and raise retention/storage.
- **SSO/OIDC milestone.** Switch `config_profile = "fedgov-cac"` (or wire your IdP), replace the
  `GF_HUMAN_OIDC_*` placeholders in `helm/agent-shield/profiles/fedgov-cac.yaml`, and
  supply the client secret out-of-band (`TF_VAR_oidc_client_secret`, or patch the
  `GF_HUMAN_OIDC_CLIENT_SECRET` key in `gf-secrets`). See `docs/cac-piv-integration.md`.
- **Lock down the API server** if required: `cluster_public_access = false` (bastion/VPN).
- **Getting support from us.** Send:
  1. `kubectl -n agent-shield get pods -o wide`
  2. Logs for the affected service — one of `audit`, `pdp`, `registry`, `identity`,
     `compliance`, `egress`, `pep`, `management`, `ui`:
     `kubectl -n agent-shield logs deploy/<service> --tail=200` (add `--previous` for a
     crash-looping pod)
  3. `terraform output` (no secrets in outputs) and your `image_tag`
  Never send us the contents of `gf-secrets` or your tfvars password hash.

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Pods `ImagePullBackOff` | Images were not mirrored into your ECR (or wrong tag) | Run `scripts/mirror_images.sh <REGION> <ACCOUNT_ID> <TAG>`; confirm all 9 report `OK` and the tag matches `image_tag` |
| `identity` crash-loops: `GF_BOOTSTRAP_ADMIN_PASSWORD_HASH must be an argon2id hash` | A plaintext-looking password was supplied — identity refuses anything that doesn't parse as `$argon2id$` | Regenerate with `python3 scripts/make_admin_hash.py`, update `bootstrap_admin_password_hash`, re-apply |
| `identity` crash-loops: `bootstrap admin misconfigured` | Only one of email/hash set — both are required together | Set both `bootstrap_admin_email` and `bootstrap_admin_password_hash` (or neither) |
| `management` refuses to start (missing `GF_IDENTITY_CONSOLE_PUBKEY`) | It runs `GF_ENV=production` and won't boot without the pinned console public key. Terraform pre-provisions this key — only manual Helm installs hit it | Populate the `gf-secrets` key from identity's `GET /v1/keys/console` (`.public_key_pem`) per the chart NOTES.txt |
| `audit` crash-loops: `GF_AUDIT_WRITER_TOKEN is required` | Fail-closed boot guard: the ledger never starts accepting unauthenticated writes. Terraform generates this token — manual installs must | Add `GF_AUDIT_WRITER_TOKEN` to `gf-secrets`; producers send it as `X-Audit-Token` |
| `registry` crash-loops: `GF_REGISTRY_WRITER_TOKEN is required` | Same fail-closed pattern for the enroll/discovery write surface | Add `GF_REGISTRY_WRITER_TOKEN` to `gf-secrets`; producers send it as `X-Registry-Token` |
| First decision is `DENY` / `NO_APPLICABLE_POLICY` | No policy has been activated for the tenant yet — fail-closed default, **expected, not a bug** | Publish + activate a policy (section 4b) |
| Enroll returns `403` | Wrong auth header — enrollment wants `X-Registry-Token` (or `X-Admin-Token`), never `Authorization: Bearer` | Send `X-Registry-Token: $GF_REGISTRY_WRITER_TOKEN` |
| Enrolled agent immediately `revoked` | Code-hash attestation fails closed: the sha256 is not on the trusted allowlist | Add the hash to `REGISTRY_TRUSTED_CODE_HASHES` (section 4a) and re-enroll |
| `console_url` prints `(ALB provisioning ...)` | The load balancer controller provisions the ALB asynchronously | Wait ~1 minute, re-run `terraform output console_url` |
