# SIEM Integration

The C08 egress streamer delivers governance decisions to the SIEM you already run. The operator console is optional.

## What the streamer does

The streamer runs off the enforcement hot path. It provides at-least-once delivery of governance events to a registered per-tenant destination. Events are mapped to OCSF (or raw webhook), deduplicated by event_id, retried with backoff, and on buffer-full the streamer drops with alert. It never blocks enforcement.

Push-on-decision is live today via the ingest API and an opt-in forward tailer (gated on EGRESS_C01_URL and EGRESS_C01_TENANTS). A bounded Backfill primitive exists for gap recovery of shed events.

## Register a destination

Register per tenant:

```
POST /v1/egress/tenants/{tenant}/destinations
{
  "type": "ocsf_siem",
  "endpoint": "https://...",
  "auth": { ... }
}
```

Supported types include `ocsf_siem`, `splunk_hec`, and `webhook`. List and delete use the same path prefix. The streamer listens on port 8087.

Ingest events with:

```
POST /v1/egress/events
```

## Concrete targets

- `splunk_hec`: Splunk HEC envelope and `Authorization: Splunk <token>` (also compatible with CrowdStrike Falcon LogScale bearer auth). Tested.
- `ocsf_siem`: PII-free OCSF JSON (Detection Finding class_uid 2004). Use for generic webhooks and for Chronicle / Sentinel ingestion endpoints.
- Chronicle and Sentinel: receive the same PII-free OCSF via `ocsf_siem` / webhook.

## OCSF event shape

Governance decisions map to the OCSF Detection Finding class. Full field list lives in the audit-event-schema doc. The mapping includes dedup keys and omits any vendor product identifiers when `EGRESS_PRODUCT_NAME` is set.

## Delivery guarantees & tuning

- At-least-once (receivers must dedup by event_id).
- Per-destination queue: EGRESS_BUFFER_SIZE (default 1024).
- Retries: EGRESS_MAX_RETRIES (default 5).
- Buffer full → drop-with-alert; never blocks enforcement (off hot path, out of band).

See docs/configuration-reference.md for the complete env-var table.

## Security

- Outbound auth: HMAC, bearer, Splunk-HEC, mTLS.
- SSRF protection: private/loopback destinations refused unless EGRESS_ALLOW_PRIVATE_DESTINATIONS=true (dev/test only).
- PII-free scan: content-bearing keys (prompt, response, body, ...) are rejected at ingest; only metadata and references leave.

## White-label

Set EGRESS_PRODUCT_NAME to brand the OCSF product field for OEM use.

## Verify

1. Register a test `ocsf_siem` or `splunk_hec` destination.
2. POST an event or drive a governance decision.
3. Confirm the event appears in the target SIEM search.