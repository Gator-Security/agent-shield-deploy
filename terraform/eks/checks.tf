# Posture checks — WARNINGS at plan/apply (never fatal, so a smoke test still works),
# making the dev-friendly defaults impossible to ship to production silently.

check "tls_configured" {
  assert {
    condition     = var.acm_certificate_arn != ""
    error_message = "acm_certificate_arn is empty: the console ALB is HTTP-ONLY. Fine for a smoke test; NEVER for production or a customer-facing POC. Issue an ACM cert for your console domain and set acm_certificate_arn."
  }
}

check "first_login_configured" {
  assert {
    condition     = var.bootstrap_admin_email != "" && var.bootstrap_admin_password_hash != ""
    error_message = "No bootstrap admin configured (bootstrap_admin_email / bootstrap_admin_password_hash): the console will have NO user to log in as after install. Generate a hash with scripts/make_admin_hash.py and set both variables."
  }
}

check "audit_ledger_durability" {
  assert {
    condition     = var.db_multi_az || var.db_instance_class != "db.t3.small"
    error_message = "RDS is single-AZ on the smallest class (trial posture; backups: 7 days, final snapshot skipped). Acceptable for a POC — for production set db_multi_az = true and review terraform/eks/rds.tf lifecycle settings."
  }
}
