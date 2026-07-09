# CAC/PIV smartcard authentication

How to authenticate Agent Shield console users with CAC/PIV smartcards. Pairs with the
`fedgov-cac` configuration profile (`helm/agent-shield/profiles/fedgov-cac.yaml`).

## Architecture: federate, don't terminate

```
CAC/PIV card ──x509 client cert──> CAC-capable OIDC IdP ──OIDC (authz code)──> C04 identity
                                                                                    │
     browser ◄── httpOnly session ── UI/BFF ◄── C04-signed console token ───────────┘
                                        │
                                        └──server-side──> management API (validates the
                                                          C04-signed token; fail-closed)
```

Agent Shield **federates** CAC through your OIDC identity provider rather than terminating
x509 client certificates itself. The smartcard/PKI machinery — DoD PKI trust chain
validation, CRL/OCSP revocation checking, certificate policy OIDs, JITC accreditation —
lives in the IdP, which is already built and accredited for it. Agent Shield consumes
standard OIDC claims, so **any CAC-capable IdP works**:

| IdP | CAC mechanism |
|-----|---------------|
| Keycloak | x509 browser authentication flow (direct cert lookup or cert-to-user mapping) |
| Okta | Smart Card / PIV as an identity provider (IdP-initiated MTLS endpoint) |
| ADFS | Certificate authentication method (AD-mapped) |

If your environment truly cannot place an IdP in the path (direct x509 termination in
Agent Shield), contact us — that is a roadmap item, not configuration.

## Setup

### 1. IdP side

1. Enable your IdP's smartcard/x509 authentication for the realm/tenant.
2. Create an OIDC client for the console (e.g. `agent-shield-console`), authorization-code
   flow, with your console origin as the redirect URI.
3. Map claims: Agent Shield needs a **roles** claim and a **tenant** claim on the ID token
   (e.g. a Keycloak protocol mapper from group membership). The claim *names* are
   configurable — they must match `GF_HUMAN_OIDC_ROLE_CLAIM` / `GF_HUMAN_OIDC_TENANT_CLAIM`
   in the profile (defaults: `roles`, `tenant_id`).

### 2. Agent Shield side

1. Edit `profiles/fedgov-cac.yaml`: replace the `GF_HUMAN_OIDC_ISSUER`, `GF_HUMAN_OIDC_JWKS_URI`,
   and `GF_HUMAN_OIDC_CLIENT_ID` placeholders with your IdP's values.
2. Put the OIDC client secret into the cluster Secret (never in values/git):
   ```bash
   kubectl -n agent-shield patch secret gf-secrets \
     -p '{"stringData":{"GF_HUMAN_OIDC_CLIENT_SECRET":"<client secret>"}}'
   ```
   (Or supply it at provision time via the Terraform `oidc_client_secret` variable /
   External Secrets.)
3. Install with the profile — Helm directly (`-f profiles/fedgov-cac.yaml`), the Terraform
   module (`config_profile = "fedgov-cac"`), or GitOps (select the profile in the
   HelmRelease `valuesFiles` — see `gitops/`).

### 3. Environment hardening that belongs with CAC

- **Internal-facing console:** Terraform `ingress_scheme = "internal"` — the ALB is only
  reachable inside your network boundary.
- **TLS mandatory:** `acm_certificate_arn` set; plain-HTTP install is for smoke tests only.
- **Private EKS endpoint:** `cluster_public_access = false`; reach the API server via your
  bastion/VPN.
- **FIPS review:** Agent Shield signs console tokens and audit decisions with Ed25519
  (approved in FIPS 186-5). If your accreditation requires FIPS 140-validated *modules*
  end-to-end, review the crypto-module inventory with us before deployment.

## What stays fail-closed

- The management API refuses to boot without the pinned console-token public key and
  derives the caller **only** from the validated token — group/role headers from the wire
  are never trusted.
- A missing `GF_HUMAN_OIDC_CLIENT_SECRET` key prevents identity from starting under this
  profile (secretEnv is required, not optional) — a CAC install can never silently run
  without its IdP credential.
- SSO does not bypass tenancy: the tenant claim maps the user into exactly one tenant, and
  cross-tenant access checks remain enforced at the gateway.
