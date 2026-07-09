# ─────────────────────────────────────────────────────────────────────────────
# AWS / naming
# ─────────────────────────────────────────────────────────────────────────────
variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "aws_profile" {
  description = "Named AWS CLI profile to use. Empty string uses the default credential chain."
  type        = string
  default     = ""
}

variable "name_prefix" {
  description = "Prefix for all created resource names (cluster, VPC, RDS, roles)."
  type        = string
  default     = "agent-shield"
}

variable "namespace" {
  description = "Kubernetes namespace the control plane is installed into."
  type        = string
  default     = "agent-shield"
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}

# ─────────────────────────────────────────────────────────────────────────────
# Network
# ─────────────────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the created VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread the cluster + RDS across (>= 2)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count must be at least 2 (EKS and RDS both require multi-AZ subnets)."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS
# ─────────────────────────────────────────────────────────────────────────────
variable "k8s_version" {
  description = "EKS control-plane Kubernetes version."
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group. The full plane (~13 pods) fits comfortably on 2x t3.large."
  type        = string
  default     = "t3.large"
}

variable "node_desired_size" {
  description = "Desired managed-node-group size."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum managed-node-group size."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum managed-node-group size."
  type        = number
  default     = 4
}

variable "cluster_public_access" {
  description = "Expose the EKS API server endpoint publicly (kubectl from anywhere). Set false to require in-VPC/bastion access."
  type        = bool
  default     = true
}

# ─────────────────────────────────────────────────────────────────────────────
# RDS (audit ledger + identity/registry persistence)
# ─────────────────────────────────────────────────────────────────────────────
variable "db_instance_class" {
  description = "RDS instance class for the audit-ledger Postgres."
  type        = string
  default     = "db.t3.small"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage (GiB)."
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "Postgres engine version for RDS."
  type        = string
  default     = "16"
}

variable "db_multi_az" {
  description = "Run RDS Multi-AZ (recommended for production durability of the audit ledger)."
  type        = bool
  default     = false
}

variable "db_username" {
  description = "Master username. MUST match the chart's config.postgresUser."
  type        = string
  default     = "gov"
}

variable "db_name" {
  description = "Initial database name. MUST match the chart's config.postgresDb."
  type        = string
  default     = "governed"
}

# ─────────────────────────────────────────────────────────────────────────────
# Application images (ECR) + chart
# ─────────────────────────────────────────────────────────────────────────────
variable "image_registry" {
  description = "ECR registry host that holds the agent-shield/* images. Defaults to this account's ECR in the target region."
  type        = string
  default     = ""
}

variable "image_repo_prefix" {
  description = "Repository namespace under the registry (image = <registry>/<prefix>/<service>:<tag>)."
  type        = string
  default     = "agent-shield"
}

variable "image_tag" {
  description = "Image tag deployed for every service. All agent-shield/* repos must carry this tag."
  type        = string
  default     = "0.1.0"
}

variable "chart_path" {
  description = "Path to the Helm chart (relative to this module) or a chart repo reference."
  type        = string
  default     = "../../helm/agent-shield"
}

variable "config_profile" {
  description = "Configuration profile layered onto the chart (a file under <chart_path>/profiles/, without .yaml). baseline = the fail-closed minimum; fedgov-cac = CAC/PIV via an OIDC IdP (requires the GF_HUMAN_OIDC_* placeholders replaced — see profiles/fedgov-cac.yaml). Empty string = chart defaults only."
  type        = string
  default     = "baseline"
}

# ─────────────────────────────────────────────────────────────────────────────
# Ingress / TLS
# ─────────────────────────────────────────────────────────────────────────────
variable "acm_certificate_arn" {
  description = "ACM cert ARN for HTTPS on the public console ALB. Empty = HTTP-only (dev/smoke-test only; NEVER expose the console over plain HTTP in production)."
  type        = string
  default     = ""
}

variable "ingress_scheme" {
  description = "ALB scheme for the public console ingress: internet-facing or internal."
  type        = string
  default     = "internet-facing"
}

# ─────────────────────────────────────────────────────────────────────────────
# Secrets
# ─────────────────────────────────────────────────────────────────────────────
variable "registry_trusted_code_hashes" {
  description = "Comma-separated sha256 hex allowlist of trusted agent code hashes (C05). Empty is valid (no agents pre-trusted)."
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "OIDC client secret for human SSO (used by the fedgov-cac profile). Empty by default; supply via TF_VAR_oidc_client_secret or patch the gf-secrets key after apply — never commit it in a tfvars file."
  type        = string
  default     = ""
  sensitive   = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Bootstrap console admin (first login)
# ─────────────────────────────────────────────────────────────────────────────
variable "bootstrap_admin_email" {
  description = "Email for the FIRST console admin (platform_admin). Identity creates it idempotently on boot. Empty = no bootstrap admin (a fresh install then has no way to log in until you create a user another way)."
  type        = string
  default     = ""
}

variable "bootstrap_admin_password_hash" {
  description = "argon2id HASH for the bootstrap admin ($argon2id$...) — generate with scripts/make_admin_hash.py. HASH-ONLY by design: the password itself never enters Terraform state or the cluster. Identity refuses plaintext-looking values."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.bootstrap_admin_password_hash == "" || startswith(var.bootstrap_admin_password_hash, "$argon2id$")
    error_message = "bootstrap_admin_password_hash must be an argon2id hash ($argon2id$...), never a plaintext password. Generate one: python3 scripts/make_admin_hash.py"
  }
}
