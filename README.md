# Agent Shield — Deployment

Everything you need to install and operate **Agent Shield**, the AI-governance control plane —
Terraform, the Helm chart, GitOps templates, and the deployment docs. This repo is the
customer-facing install surface; the product images are distributed separately (see below).

## What's here

| Path | What it is |
|------|-----------|
| [`terraform/eks/`](terraform/eks/) | Turnkey Terraform: VPC + EKS + RDS + the chart, in one `apply`. Start here for a fresh AWS install. |
| [`helm/agent-shield/`](helm/agent-shield/) | The Helm chart + configuration [`profiles/`](helm/agent-shield/profiles/) (`baseline`, `fedgov-cac`). Use directly on an existing cluster. |
| [`gitops/`](gitops/) | Config-as-code: a repo template + Flux wiring so changes land via reviewed pull requests. |
| [`scripts/`](scripts/) | `mirror_images.sh` (copy the images into your registry) and `make_admin_hash.py` (first-login admin). |
| [`security/cosign.pub`](security/cosign.pub) | Public key to verify image signatures — see [docs/image-verification.md](docs/image-verification.md). |
| [`docs/`](docs/) | Runbook, deployment guide, configuration reference, service catalog, CAC/PIV, SIEM, and more. |

## Quick start (AWS / EKS)

1. **Get image access.** Your Agent Shield contact grants your AWS account read-only pull
   access to the images (and gives you the source registry values).
2. **Mirror the images** into your own registry:
   ```bash
   VENDOR_REGISTRY=<given-to-you> VENDOR_REGION=<given-to-you> \
     scripts/mirror_images.sh <your-region> <your-account-id> 0.1.0
   ```
3. **Install** with Terraform:
   ```bash
   cd terraform/eks
   cp terraform.tfvars.example terraform.tfvars   # set your values
   python3 ../../scripts/make_admin_hash.py        # first console admin (argon2id hash)
   terraform init && terraform apply
   ```
4. Follow **[docs/poc-runbook.md](docs/poc-runbook.md)** from there — first login, first
   agent enrolled, first policy, first audited decision.

Already run your own EKS cluster? Use the Helm chart directly — see
[docs/deployment-guide.md](docs/deployment-guide.md).

## Security posture (built in)

- **Fail-closed by default** — the control plane refuses to boot accepting unauthenticated
  writes; required tokens are generated at install.
- **Only the console is public** — the management plane stays cluster-internal.
- **Signed, minimal images** — every image is Chainguard-based and cosign-signed; verify with
  [`security/cosign.pub`](security/cosign.pub).
- **Secrets never in Git** — the chart consumes a pre-created Secret; this repo ships key
  *names* and examples only.

## License

Apache-2.0 — see [LICENSE](LICENSE).
