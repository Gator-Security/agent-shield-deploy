# Service Catalog

This is the single at-a-glance map of every service that runs in the stack: language, port, health endpoint, dependencies, and scale profile. Operators use it as the "what am I deploying" reference (see deployment-guide for the *how*).

## Component Roles (from architecture-overview)
- **C01 audit-store**: Py service storing audit events.
- **C02 pdp**: Go policy decision engine.
- **C03 pep**: Py gateway enforcing decisions.
- **C04 identity**: Py identity and access service.
- **C05 registry**: Py agent registry and discovery.
- **C06 compliance**: Py GRC/compliance engine.
- **C07 management-api**: Go management API.
- **C08 egress**: Go SIEM streamer (governance events → SOC).

## Service Table

| service | comp | language | port | health path | depends-on |
|---------|------|----------|------|-------------|------------|
| audit-store | C01 | Py | 8080 | `/healthz`, `/readyz` | Postgres |
| pdp | C02 | Go | 8082 | confirm at deploy | audit-store |
| pep | C03 | Py | 8083 | `/health` | pdp, audit-store |
| identity | C04 | Py | 8084 | `/health` | (durable store path) |
| registry | C05 | Py | 8085 | `/health` | audit-store, identity, pdp |
| compliance | C06 | Py | 8086 | `/healthz` | audit-store |
| egress | C08 | Go | 8087 | confirm at deploy | audit-store |
| egress-firewall | — | Py | 8088 | `/health` | pdp |
| management-api | C07 | Go | 8090 | confirm at deploy | pdp, audit-store, compliance, registry |
| ui (console + BFF) | — | Next.js | 3000 | `/` | management-api, identity |

**Console**: the `ui` service is the browser console and its Backend-for-Frontend. In BFF mode it proxies to the management-api server-side and exchanges the session with identity, so it depends on both. It is the only public-facing service; the management-api stays internal.

**Egress distinction**: `egress-firewall` is the outbound chokepoint proxy (governs agent egress). `egress` (C08) is the SIEM streamer. They are distinct services with distinct ports.

## Dependency / Bring-up Order
Postgres → audit-store + pdp → identity → registry → pep + compliance + egress + egress-firewall → management-api.

## Scale Profile
Stateless services (pdp, pep, identity, registry, compliance, egress, egress-firewall, management-api) can scale horizontally. Stateful services (audit-store) require durable volumes; see configuration-reference for durability paths.
