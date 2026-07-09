# Deployment Guide

This guide takes an operator from a clean host to a correctly-configured, durable, fail-closed Agent Shield deployment. It covers the Helm install path, the required persistent volumes, TLS and secrets posture, and the fail-closed checklist.

## Prerequisites

- A container runtime (Docker or a Kubernetes cluster with Helm).
- Postgres for the audit ledger and identity/registry persistence.
- A TLS terminator in front of the deployment (services speak plain HTTP internally).
- A secrets store to supply signing keys.

Terraform is not provided.

## Topology and Trust Boundaries

TLS is terminated at the edge. Enforcement points (PEP gateway, egress-firewall) sit in front of the PDP. The audit store (backed by Postgres) records decisions and events. Identity, registry, compliance, management-api, and egress sit behind the enforcement layer. Trust boundaries are enforced by admin tokens and authenticated writer tokens on every privileged path.

## Bring-up Order

Start services in dependency order and health-gate each step:

1. Postgres
2. Audit store + PDP (everyone depends on these)
3. Identity
4. Registry
5. PEP + compliance + egress + egress-firewall
6. Management API

## Per-service Deployment

Install with the Helm chart under `helm/agent-shield/`. Compose and kustomize install paths are available from your Agent Shield contact if you need them.

See service-catalog.md for ports and dependencies and configuration-reference.md for the full env-var vocabulary. Each service ships with a health endpoint; wait for healthy before proceeding to the next layer.

## Persistent Volume Requirements

Persistent volumes are the operator's #1 correctness step. The following paths must survive a restart:

- `PDP_KILL_STORE_PATH` (`/data/kill.json`): durable kill-switch. Without it a restart silently re-enables killed agents.
- `GF_IDENTITY_DURABLE_STORE_PATH`: revocation and consumed-jti stores. Without it revoked tokens are re-accepted after restart.
- `GF_AUDIT_WAL_PATH` (`/data/audit.wal`): buffered audit events. Without it events are dropped on restart.
- Postgres data directory (`gf-db-data`): audit ledger plus identity/registry persistence.

These mounts are declared in the Helm chart's per-service PVCs.

## TLS and Secrets

Terminate TLS at the edge; never expose service ports publicly. Supply `GF_IDENTITY_PRIVATE_KEY_*`, `AUDIT_SIGNING_MASTER_KEY`, and other signing keys from a secret store, not from env files. The Helm chart uses an existing-Secret posture: secrets are never passed through Helm values.

## Fail-closed Checklist

Before exposing the deployment, confirm:

- `GF_FAIL_MODE=closed`
- `EGRESS_FAIL_OPEN=false`
- `EGRESS_PDP_URL` set and reachable
- `EGRESS_ALLOW_PRIVATE_DESTINATIONS=false`
- `ALLOW_DEV_SEED` unset
- `REGISTRY_SIGSTORE_TEST_*` unset

See configuration-reference.md for full semantics.

## Single-instance Durability Limit (V1)

Kill-switch, revocation, and consumed-jti stores are file/SQLite-backed and are **not shared across replicas**. If you scale PDP or identity past one replica without a shared Postgres store (`GF_IDENTITY_REPLAY_DSN` / `DATABASE_URL`), a killed agent, revoked token, or replayed jti accepted on one replica may still be honored by another. Read this limit before the scaling section.

## Scaling and Upgrades

Stateless services may be scaled horizontally. Services holding durable state (PDP kill store, identity revocation/jti, audit WAL, Postgres) remain single-instance in V1 unless a shared Postgres DSN is configured. Perform rolling upgrades in the same dependency order as bring-up. See the operations-runbook (P1) for backup/restore procedures.

## Verify

Run the golden-path verification from service-catalog.md against the deployed endpoints. All health checks must pass and the fail-closed checklist must hold.