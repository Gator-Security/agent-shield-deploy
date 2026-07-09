# Configuration Reference

This document is the authoritative list of every environment variable used by the services. Each table lists the variable name, its default (when known from code or deployment manifests), its effect, and the safety note for production deployments. An operator must be able to configure a production deployment from this document alone.

## Safety-Critical Callout

The following variables directly affect kill-switch durability, audit WAL durability, fail-closed enforcement, chokepoint behavior, SSRF protection, dev-seed isolation, and private-key material. A wrong or missing value for any of these silently weakens governance:

- `PDP_KILL_STORE_PATH`
- `GF_IDENTITY_DURABLE_STORE_PATH`
- `GF_AUDIT_WAL_PATH`
- `GF_FAIL_MODE`
- `EGRESS_FAIL_OPEN`
- `EGRESS_PDP_URL`
- `EGRESS_ALLOW_PRIVATE_DESTINATIONS`
- `ALLOW_DEV_SEED`
- `AUDIT_SIGNING_MASTER_KEY`
- `GF_IDENTITY_PRIVATE_KEY_PEM` / `GF_IDENTITY_PRIVATE_KEY_PATH`
- `COMPLIANCE_SIGNING_KEY_PATH`

## Conventions

Each row contains: variable name, default, effect, safety note. Ports are referenced by their environment-variable names (`PDP_PORT`, `EGRESS_PORT`, etc.). Port-collision reconciliation is documented in the service catalog.

Environment-variable prefixes are inconsistent across services (`GF_`, `EGRESS_`, `PDP_`, `MGMT_`, `COMPLIANCE_`, `REGISTRY_`, and unprefixed names such as `DATABASE_URL`). Inter-service URL aliases (`AUDIT_STORE_URL` / `PDP_AUDIT_URL` / `AUDIT_URL`) are accepted as-is for V1.

## C01 audit-store

| Variable                    | Default          | Effect                                      | Safety note                                      |
|-----------------------------|------------------|---------------------------------------------|--------------------------------------------------|
| DATABASE_URL                | —                | Connection string for audit events          | Required for durability                          |
| AUDIT_SIGNING_MASTER_KEY    | —                | Per-tenant Ed25519 signing key              | Without it signatures degrade                    |
| GF_TRUSTED_PEP_KEYS_PATH    | —                | Path to trusted PEP public keys             | Required for signature verification              |

## C02 pdp

| Variable            | Default | Effect                                      | Safety note                                      |
|---------------------|---------|---------------------------------------------|--------------------------------------------------|
| PDP_PORT / PORT     | —       | Listen port                                 | Reference only; see service-catalog              |
| PDP_INSTANCE_ID     | —       | Instance identifier                         | —                                                |
| PDP_AUDIT_URL / AUDIT_STORE_URL / AUDIT_URL | — | Audit sink URL                     | Aliases accepted for V1                          |
| PDP_PACK_POLICY / PDP_PACK_POLICY_FILE | — | Pack-level policy source        | —                                                |
| PDP_HOST_POLICY / PDP_HOST_POLICY_FILE | — | Host-level policy source       | —                                                |
| PDP_KILL_STORE_PATH | —       | Durable kill-switch store path              | Must be a persistent volume; otherwise lost on restart |

## C03 pep gateway

| Variable            | Default | Effect                                      | Safety note                                      |
|---------------------|---------|---------------------------------------------|--------------------------------------------------|
| GF_TENANT_ID        | —       | Tenant identifier                           | —                                                |
| GF_AGENT_ID         | —       | Agent identifier                            | —                                                |
| GF_PDP_ENDPOINT     | —       | PDP URL                                     | —                                                |
| GF_AUDIT_ENDPOINT   | —       | Audit URL                                   | —                                                |
| GF_FAIL_MODE        | closed  | Enforcement mode on PDP failure             | Must be `closed` in prod                         |
| GF_TIMEOUT_MS       | —       | Request timeout                             | —                                                |
| GF_CACHE_TTL        | —       | Cache TTL                                   | —                                                |
| GF_KILL_SWITCH      | —       | Kill-switch toggle                          | —                                                |
| GF_AUDIT_WAL_PATH   | —       | Durable audit WAL path                      | Must be a persistent volume                      |
| GF_UPSTREAM_BASE    | —       | Upstream base URL                           | —                                                |

## C04 identity

| Variable                         | Default | Effect                                      | Safety note                                      |
|----------------------------------|---------|---------------------------------------------|--------------------------------------------------|
| PORT                             | —       | Listen port                                 | —                                                |
| HOST                             | —       | Listen host                                 | —                                                |
| LOG_LEVEL                        | —       | Log verbosity                               | —                                                |
| GF_IDENTITY_ISSUER               | —       | Token issuer                                | —                                                |
| GF_IDENTITY_DEFAULT_TTL          | —       | Default token TTL                           | —                                                |
| GF_IDENTITY_MAX_TTL              | —       | Maximum token TTL                           | —                                                |
| GF_IDENTITY_PRIVATE_KEY_PEM / _PATH | —    | Private signing key material                | Unset yields ephemeral dev key; prod must set    |
| GF_IDENTITY_DURABLE_STORE_PATH   | —       | Revocation + jti replay store               | Must be a persistent volume                      |
| GF_IDENTITY_DATA_DIR             | —       | Data directory                              | —                                                |
| GF_IDENTITY_EPHEMERAL            | —       | Ephemeral mode flag                         | —                                                |

## C05 registry

| Variable                  | Default | Effect                                      | Safety note                                      |
|---------------------------|---------|---------------------------------------------|--------------------------------------------------|
| REGISTRY_PORT / PORT      | —       | Listen port                                 | —                                                |
| HOST                      | —       | Listen host                                 | —                                                |
| DATABASE_URL / REGISTRY_DATABASE_URL / REGISTRY_DB_PATH | — | Database connection / path | —                                   |
| AUDIT_STORE_URL           | —       | Audit sink                                  | —                                                |
| IDENTITY_URL              | —       | Identity service URL                        | —                                                |
| PDP_URL                   | —       | PDP URL                                     | —                                                |
| ALLOW_DEV_SEED            | —       | Allow development seeding                   | Must be false/unset in prod                      |
| REGISTRY_SIGSTORE_STAGING | —       | Sigstore staging endpoint                   | Non-prod only                                    |
| REGISTRY_SIGSTORE_TEST_*  | —       | Sigstore test configuration                 | Test-only                                        |

## C06 compliance

| Variable                   | Default | Effect                                      | Safety note                                      |
|----------------------------|---------|---------------------------------------------|--------------------------------------------------|
| AUDIT_STORE_URL            | —       | Audit sink                                  | —                                                |
| COMPLIANCE_ARTIFACT_ROOT   | —       | Artifact storage root                       | —                                                |
| COMPLIANCE_PRODUCT_NAME    | —       | White-label product name                    | —                                                |
| COMPLIANCE_SIGNING_KEY_PATH| —       | Signing key for compliance artifacts        | Required for integrity                           |
| COMPLIANCE_VERIFY_HINT     | —       | Verification hint                           | —                                                |

## C07 management-api

| Variable         | Default | Effect                                      | Safety note                                      |
|------------------|---------|---------------------------------------------|--------------------------------------------------|
| MGMT_PORT / PORT | —       | Listen port                                 | —                                                |
| MGMT_PRODUCT_NAME| —       | White-label product name                    | —                                                |
| AUDIT_STORE_URL  | —       | Audit sink                                  | —                                                |
| COMPLIANCE_URL   | —       | Compliance service URL                      | —                                                |
| PDP_URL          | —       | PDP URL                                     | —                                                |
| REGISTRY_URL     | —       | Registry URL                                | —                                                |

## C08 egress streamer

| Variable                           | Default | Effect                                      | Safety note                                      |
|------------------------------------|---------|---------------------------------------------|--------------------------------------------------|
| EGRESS_PORT / PORT                 | —       | Listen port                                 | —                                                |
| EGRESS_BUFFER_SIZE                 | —       | Buffer size                                 | —                                                |
| EGRESS_MAX_RETRIES                 | —       | Max retry count                             | —                                                |
| EGRESS_ALLOW_PRIVATE_DESTINATIONS  | false   | Allow private IP destinations               | Keep false in prod (SSRF protection)             |
| EGRESS_PRODUCT_NAME                | —       | White-label product name                    | —                                                |

## egress-firewall chokepoint

| Variable          | Default | Effect                                      | Safety note                                      |
|-------------------|---------|---------------------------------------------|--------------------------------------------------|
| EGRESS_PORT       | —       | Listen port                                 | —                                                |
| HOST              | —       | Listen host                                 | —                                                |
| EGRESS_TENANT_ID  | —       | Tenant identifier                           | —                                                |
| EGRESS_AGENT_ID   | —       | Agent identifier                            | —                                                |
| EGRESS_AGENT_RISK | —       | Agent risk level                            | —                                                |
| EGRESS_PDP_URL    | —       | Real PDP URL for the chokepoint             | When unset, falls back to local-only DLP         |
| EGRESS_FAIL_OPEN  | false   | Fail-open on PDP outage                     | Must remain false; true bypasses the chokepoint  |

## Persistent-Volume Requirements

The following paths must be backed by persistent volumes so their contents survive container restarts:

- `PDP_KILL_STORE_PATH` — durable kill-switch state (otherwise the kill switch becomes in-memory only).
- `GF_IDENTITY_DURABLE_STORE_PATH` — revocation list and jti replay protection.
- `GF_AUDIT_WAL_PATH` — append-only audit write-ahead log.

These paths are referenced directly by the variables above; the concrete hostPath or PVC names are supplied by the Kubernetes manifests.