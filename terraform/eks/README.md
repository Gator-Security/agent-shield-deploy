# Agent Shield — EKS Terraform

Turnkey Terraform that stands up the full Agent Shield control plane on a **new** Amazon EKS
cluster in one `terraform apply`: VPC, EKS + managed nodes, the AWS Load Balancer Controller,
a managed **RDS Postgres** audit ledger, all secrets, and the Helm chart behind a public
console ALB.

> This module **creates** its own VPC and cluster. To deploy onto an EKS cluster you already
> run, use the Helm chart directly (`helm/agent-shield`) — see the deployment guide.

## What it creates

| Layer | Resource |
|-------|----------|
| Network | VPC (`10.42.0.0/16`), public + private subnets across N AZs, single NAT |
| Cluster | EKS control plane + one managed node group (`t3.large` × 2 by default) |
| Add-ons | vpc-cni, coredns, kube-proxy, EBS CSI (IRSA), AWS Load Balancer Controller (IRSA), gp3 default StorageClass |
| Database | RDS Postgres (private, encrypted) — the audit ledger + identity/registry store |
| Secrets | `gf-secrets` (all tokens + signing keys generated in-run; **never** passed through Helm values) |
| App | The `agent-shield` umbrella chart (9 services) + a public console Ingress → ALB |
| Config | A configuration profile layered onto the chart (`config_profile`, default `baseline` — see `../../helm/agent-shield/profiles/`) |

## Prerequisites

- Terraform ≥ 1.6, the `aws` CLI, `kubectl`, and `python3` with the `cryptography` package
  (used once to mint the console-identity keypair).
- AWS credentials with permission to create the resources above.
- The `agent-shield/*` images in ECR **in your account/region**, all carrying `image_tag`
  (default `0.1.0`). Get them there with the mirror flow below — **do this first**, or every
  pod lands in `ImagePullBackOff`.

## Step 0 — mirror the images into your ECR

1. Give your Agent Shield contact your 12-digit AWS account id; they grant your account
   read-only pull access to the `agent-shield/*` image repositories (revocable, pull-only).
2. Mirror all 9 images into your account:

```bash
scripts/mirror_images.sh <your-region> <your-account-id> 0.1.0
```

The script logs into both registries, creates the `agent-shield/*` repositories in your
account, copies the images, and verifies every tag before exiting.

## Usage

```bash
cd terraform/eks
cp terraform.tfvars.example terraform.tfvars

# first console login: generate the argon2id hash (password never enters TF state)
python3 ../../scripts/make_admin_hash.py     # needs: pip install argon2-cffi
# -> set bootstrap_admin_email + bootstrap_admin_password_hash in terraform.tfvars

terraform init
terraform apply

# point kubectl at the cluster
$(terraform output -raw configure_kubectl)

# open the console and log in with the bootstrap admin
terraform output console_url
```

For the full first-hour walkthrough (first agent enrolled, first policy, first audited
decision), see [docs/poc-runbook.md](../../../docs/poc-runbook.md).

### Teardown

```bash
terraform destroy
```

A pre-destroy hook removes the Ingress while the AWS Load Balancer Controller is still running,
so the ALB and its `elbv2.k8s.aws/resources` finalizers drain cleanly (otherwise an orphaned
finalizer hangs the namespace in `Terminating` and blocks VPC/NAT deletion). This needs `kubectl`
and `aws` on the machine running `destroy`.

If a destroy ever wedges on a `Terminating` namespace or a `DependencyViolation` on subnets,
clear the stuck finalizer and re-run:

```bash
kubectl get ns agent-shield -o json | jq 'del(.spec.finalizers)' \
  | kubectl replace --raw /api/v1/namespaces/agent-shield/finalize -f -
terraform destroy
```

## The console-key bootstrap (why a single apply works)

The management-api runs `GF_ENV=production` and **refuses to boot** without the Ed25519 public
key it uses to validate C04-signed browser tokens — which C04 (identity) normally generates on
first boot. To avoid a two-phase install, the seed is generated up front as a **persisted
`random_id`** (stable across applies — the key does not rotate every `terraform apply`) and
`scripts/gen-console-key.py` derives *only* the matching public key from it. The raw seed is
mounted into identity (so C04 adopts it instead of generating an ephemeral one) and the public
PEM is pinned by management-api. Both halves exist before any pod starts, so the whole plane
converges in one apply. The private seed never appears in a data-source result, plan output, or
CI log — it lives only in the (gitignored) state and the in-cluster Secret.

## Security posture (preserved from the chart)

- **Only the console is public.** The Ingress exposes `/` → the UI only; the management Service
  stays ClusterIP and `:8090` is never routed to the public ALB. The browser reaches the
  management plane exclusively through the UI's server-side BFF (`NEXT_PUBLIC_USE_BFF=true`),
  which attaches a short-lived C04-signed token to each cluster-internal call. This matches the
  chart's NOTES.txt rule ("keep :8090 off the public internet") — the token wall is
  defense-in-depth, not the only wall.
- **TLS:** set `acm_certificate_arn` for HTTPS + HTTP→HTTPS redirect. HTTP-only (no cert) is for
  smoke tests only.
- **RDS is private** — reachable only from the node group security group.
- **Fail-closed by default:** audit store and registry run `*_ENV=production`, so they crash-loop
  rather than boot accepting unauthenticated writes. All required tokens are generated here.

## Production hardening checklist

- **Remote state first**: copy `backend.tf.example` → `backend.tf` (S3 + SSE-KMS + DynamoDB
  lock) and `terraform init -migrate-state`. State holds the signing seed, DB password, and
  all tokens in plaintext — it must live encrypted, versioned, and access-controlled.
- Supply `acm_certificate_arn` (never expose the console over plain HTTP).
- `db_multi_az = true` and raise `db_allocated_storage` / backup retention.
- Consider `cluster_public_access = false` (reach the API server via a bastion/VPN).
- Manage `gf-secrets` with AWS Secrets Manager + the External Secrets Operator instead of
  Terraform-generated values if your compliance regime requires it.
- Pin `image_tag` to an immutable release tag, not `latest`.
