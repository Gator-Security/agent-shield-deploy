# Egress Chokepoint Deployment

## 1. Why a chokepoint vs an SDK

An SDK integration is opt-in and in-process: an agent can simply avoid calling the governed path. A chokepoint forces every outbound request through a proxy that consults the central PDP, so governance is applied regardless of agent code. The trust model changes from "developers remembered to integrate" to "network traffic must traverse the enforcement point."

## 2. Two chokepoint forms

**Egress proxy** (the egress-firewall): agents send outbound HTTP through the proxy via `HTTP_PROXY`, a base-URL override, or explicit calls to `/v1/egress/forward`. Suitable for existing agents that can be configured to use a proxy. CONNECT is supported for TLS tunneling but creates a blind tunnel: the proxy cannot inspect or classify the inner traffic, making the tunnel opaque and allowing potential bypass(es) classification of protected content.

**PEP gateway** : the gateway fronts a specific tool or endpoint over TLS. Agents call the gateway URL; the gateway enforces policy before forwarding. Use this form when you control the target endpoint or need TLS termination/inspection.

Choose the egress proxy when you need a general outbound choke for arbitrary destinations; choose the PEP gateway when fronting one or more known tools.

## 3. Deploy the egress proxy

Run the proxy container (or `python -m egress.proxy`). It listens on port 8088 by default.

Wire the central PDP so tenant policy governs decisions:

```
EGRESS_PDP_URL=http://pdp:8080
```

`EGRESS_FAIL_OPEN` defaults to false (fail-closed). When the PDP is unreachable the proxy denies protected egress. In production (`GF_ENV=production`) the proxy refuses to start with `EGRESS_FAIL_OPEN=true`. See the configuration-reference doc for the full set of environment variables and their defaults.

The governed identity comes from the deployment environment (`EGRESS_TENANT_ID`, `EGRESS_AGENT_ID`, `EGRESS_AGENT_RISK`). A request body attempting to override these values is rejected with HTTP 403 (`identity_override_forbidden`). Client headers are not trusted for identity in production.

## 4. Make it unbypassable via network-enforced egress

The proxy alone is opt-in and can be routed around. Unbypassability requires network policy that forces all egress through the proxy.

Configure the agent's security group, subnet, firewall, or Kubernetes NetworkPolicy so the agent pod or VM can reach only the proxy IP/port. Direct egress to model endpoints, the public internet, or metadata services must be blocked at the network layer.

Example: AWS security-group egress rule allowing traffic only to the proxy (replace `proxy-sg` and CIDR as appropriate):

```
aws ec2 authorize-security-group-egress \
  --group-id sg-agent \
  --protocol tcp \
  --port 8088 \
  --source-group proxy-sg
```

(The inverse rule denying all other outbound destinations is also required.) The resulting property is network-enforced egress: the agent physically cannot reach a destination without traversing the chokepoint.

No NetworkPolicy manifest is shipped with the chart. Operators apply an equivalent rule for their environment.

## 5. What happens at the chokepoint

1. Classify the request (local DLP layer).
2. Consult the PDP via `EGRESS_PDP_URL` when configured.
3. Combine outcomes with deny-wins (`most_restrictive`): DENY > REQUIRE_APPROVAL > ALLOW.
4. Fail-closed on PDP unavailability unless `EGRESS_FAIL_OPEN=true` (refused in production).
5. Apply redaction obligations before forwarding.
6. Forward on ALLOW, return 403/428 on DENY/REQUIRE_APPROVAL.
7. The PDP records the decision in the C01 audit store.

## 6. Verify it's closed

Two required tests:

- PDP-down test: stop the PDP service, then attempt a protected egress request through the proxy. The request must be denied (reason `PDP_UNAVAILABLE` or equivalent) rather than allowed.
- Direct-egress test: from the agent, attempt a connection that bypasses the proxy. The network policy must block it.

Both tests must pass before declaring the deployment enforced.

## 7. Observability

The proxy emits these response headers on every governed request:

- `x-egress-pdp-consulted`
- `x-egress-pdp-available`
- `x-egress-pdp-latency-ms`
- `x-egress-pdp-decision`

Use them to confirm the central PDP path is active and to measure added latency.