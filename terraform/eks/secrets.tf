# The application namespace. Created before the Secret + release so both land in it.
resource "kubernetes_namespace" "app" {
  metadata {
    name   = var.namespace
    labels = { "app.kubernetes.io/part-of" = "agent-shield" }
  }

  depends_on = [module.eks]
}

# ── Generated secret material (never leaves the cluster / state) ──
# Admin + writer + auditor tokens: `openssl rand -hex 32` equivalents.
resource "random_id" "admin_token" { byte_length = 32 }
resource "random_id" "auditor_token" { byte_length = 32 }
resource "random_id" "audit_writer_token" { byte_length = 32 }
resource "random_id" "registry_writer_token" { byte_length = 32 }
resource "random_id" "action_token_secret" { byte_length = 32 }

# C01 per-tenant checkpoint signing root: base64 of >= 32 bytes.
resource "random_id" "audit_signing_master_key" { byte_length = 48 }

# C04 console-identity keypair. The 32-byte seed is a PERSISTED random_id (stable across
# applies — the console key does not rotate on every `terraform apply`), and its value is only
# known after apply (never printed at plan time). gen-console-key.py derives ONLY the public
# key from it, so the private seed never appears in a data-source result / plan output / logs.
# Pre-provisioning both halves is what lets management-api (GF_ENV=production) boot in the same
# apply that starts identity.
resource "random_id" "console_seed" {
  byte_length = 32
}

data "external" "console_pubkey" {
  program = ["python3", "${path.module}/scripts/gen-console-key.py"]
  query = {
    seed_b64 = random_id.console_seed.b64_std
  }
}

# The single Secret the chart consumes (existingSecret). Secret material is created here and
# referenced by key name only from the chart — never passed through Helm values.
resource "kubernetes_secret" "gf_secrets" {
  metadata {
    name      = "gf-secrets"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    AUDIT_DATABASE_URL           = local.audit_database_url
    POSTGRES_PASSWORD            = random_password.db.result
    AUDIT_SIGNING_MASTER_KEY     = random_id.audit_signing_master_key.b64_std
    REGISTRY_TRUSTED_CODE_HASHES = var.registry_trusted_code_hashes
    GF_ADMIN_TOKEN               = random_id.admin_token.hex
    GF_AUDITOR_TOKEN             = random_id.auditor_token.hex
    GF_AUDIT_WRITER_TOKEN        = random_id.audit_writer_token.hex
    GF_REGISTRY_WRITER_TOKEN     = random_id.registry_writer_token.hex
    GF_ACTION_TOKEN_SECRET       = random_id.action_token_secret.hex
    # C04-signed console-token validation key pinned by the management-api gateway.
    GF_IDENTITY_CONSOLE_PUBKEY = data.external.console_pubkey.result.public_pem
    # OIDC client secret for human SSO (the fedgov-cac profile maps it via secretEnv).
    # Placeholder here so the key always exists; populate it for SSO/CAC installs:
    #   kubectl -n <ns> patch secret gf-secrets -p '{"stringData":{"GF_HUMAN_OIDC_CLIENT_SECRET":"<value>"}}'
    GF_HUMAN_OIDC_CLIENT_SECRET = var.oidc_client_secret
    # Bootstrap console admin (first login). Hash-only — identity refuses plaintext-looking
    # values, and the password itself never exists in state. Empty keys = no bootstrap user.
    GF_BOOTSTRAP_ADMIN_EMAIL         = var.bootstrap_admin_email
    GF_BOOTSTRAP_ADMIN_PASSWORD_HASH = var.bootstrap_admin_password_hash
  }

  # Raw 32-byte Ed25519 seed mounted as a file into identity. binary_data values are
  # base64-encoded; random_id.b64_std is the base64 of the 32 raw bytes, and the kubelet writes
  # the decoded 32 bytes to the mounted path — exactly what load_or_create() reads. The seed
  # lives only here (a sensitive Secret) and in random_id state (gitignored) — never in a
  # data-source result or plan output.
  binary_data = {
    GF_CONSOLE_SIGNING_KEY = random_id.console_seed.b64_std
  }

  type = "Opaque"
}
