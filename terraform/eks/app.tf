# The control-plane umbrella chart. Overrides:
#   - images repointed at the customer's ECR (imagePrefix + tag)
#   - bundled Postgres OFF; the audit DSN in gf-secrets points at RDS
#   - identity adopts the pre-generated console key via a mounted secret file, so the
#     management-api gateway (GF_ENV=production) boots with its pinned pubkey already present.
# Secrets never travel through values — only the pre-created gf-secrets Secret's KEY NAMES do.
resource "helm_release" "agent_shield" {
  name      = "agent-shield"
  chart     = var.chart_path
  namespace = kubernetes_namespace.app.metadata[0].name

  wait          = true
  timeout       = 900
  atomic        = false # keep failed resources for diagnosis rather than silent rollback
  wait_for_jobs = true  # block on the one-shot alembic migration Job

  # Later entries win on conflicts (per-key deep merge): profile first, then the module's
  # own overrides — so a profile can never clobber the RDS/image/secret wiring.
  values = concat(
    var.config_profile != "" ? [file("${var.chart_path}/profiles/${var.config_profile}.yaml")] : [],
    [yamlencode({
      imagePrefix    = local.image_prefix
      tag            = var.image_tag
      existingSecret = kubernetes_secret.gf_secrets.metadata[0].name

      # Managed RDS instead of the in-cluster Postgres.
      postgres  = { enabled = false }
      migration = { enabled = true }

      config = {
        postgresUser = var.db_username
        postgresDb   = var.db_name
      }

      services = {
        identity = {
          # Mount the raw Ed25519 seed as a read-only file and point C04 at it (overrides the
          # chart's /data default), so identity adopts THIS key instead of self-generating one.
          fileSecretMounts = [{
            secretKey = "GF_CONSOLE_SIGNING_KEY"
            mountPath = "/console-key"
            fileName  = "console-signing.key"
          }]
          env = {
            GF_CONSOLE_SIGNING_KEY_PATH = "/console-key/console-signing.key"
          }
          # First-login bootstrap: identity creates this platform_admin idempotently on
          # boot (both keys empty = no-op; only one set = identity refuses startup, loudly).
          optionalSecretEnv = {
            GF_BOOTSTRAP_ADMIN_EMAIL         = "GF_BOOTSTRAP_ADMIN_EMAIL"
            GF_BOOTSTRAP_ADMIN_PASSWORD_HASH = "GF_BOOTSTRAP_ADMIN_PASSWORD_HASH"
          }
        }
      }
  })])

  depends_on = [
    kubernetes_secret.gf_secrets,
    aws_db_instance.this,
    kubernetes_storage_class_v1.gp3,
    module.eks,
  ]
}

# Public console ingress → ALB. ONLY the UI console is exposed. The management Service stays
# ClusterIP; :8090 is never public (the browser reaches it only via the UI's server-side BFF).
locals {
  ingress_annotations = merge(
    {
      "alb.ingress.kubernetes.io/scheme"           = var.ingress_scheme
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/"
      # The UI root answers 200 (or a 3xx redirect to the login route) — accept both so the
      # single UI target group stays healthy.
      "alb.ingress.kubernetes.io/success-codes" = "200-399"
    },
    var.acm_certificate_arn != "" ? {
      "alb.ingress.kubernetes.io/certificate-arn" = var.acm_certificate_arn
      "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
    } : {}
  )
}

resource "kubernetes_ingress_v1" "console" {
  metadata {
    name        = "agent-shield"
    namespace   = kubernetes_namespace.app.metadata[0].name
    annotations = local.ingress_annotations
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        # ONLY the console (UI) is public. The browser reaches the management plane exclusively
        # through the UI's server-side BFF (NEXT_PUBLIC_USE_BFF=true -> the Next.js /api/gf/*
        # routes proxy to management over the cluster-internal Service), so there is NO public
        # /api -> :8090 route. The chart's NOTES.txt requires :8090 stay off the public internet;
        # routing /api here would put the full authenticated management surface on the ALB and
        # remove the last wall in front of a compromised token. management stays ClusterIP.
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "ui"
              port { number = 3000 }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.agent_shield,
    helm_release.aws_load_balancer_controller,
  ]

  # The ALB is provisioned asynchronously by the controller; give it time to report hostname.
  timeouts {
    create = "10m"
  }
}

# TEARDOWN ORDERING (critical). The AWS Load Balancer Controller attaches the finalizer
# `elbv2.k8s.aws/resources` to the Ingress and to the TargetGroupBinding it creates. Those
# finalizers can only be removed by the controller. If Terraform tears the controller down
# before those objects are gone, the finalizers stick forever: the namespace hangs in
# Terminating, the ALB is orphaned, and VPC/subnet/NAT deletion fails with DependencyViolation
# — wedging the whole destroy. This resource deletes the Ingress FIRST, while the controller is
# still running (so it can drain the ALB + TargetGroupBindings + finalizers cleanly). It runs
# before the controller on destroy because it depends_on it (destroy = reverse dependency order).
resource "null_resource" "ingress_predestroy_cleanup" {
  triggers = {
    cluster = module.eks.cluster_name
    region  = var.region
    ns      = kubernetes_namespace.app.metadata[0].name
    profile = var.aws_profile
  }

  provisioner "local-exec" {
    when = destroy
    # Best-effort (|| true): a customer without kubectl/aws on the destroy host, or a cluster
    # already gone, must not wedge the destroy — they can still fall back to a manual namespace
    # finalize. When present, this makes the common path clean.
    command = <<-EOT
      aws eks update-kubeconfig --name ${self.triggers.cluster} --region ${self.triggers.region} ${self.triggers.profile != "" ? "--profile ${self.triggers.profile}" : ""} >/dev/null 2>&1 || true
      kubectl delete ingress --all -n ${self.triggers.ns} --ignore-not-found --timeout=5m || true
      kubectl wait --for=delete targetgroupbinding --all -n ${self.triggers.ns} --timeout=5m 2>/dev/null || true
      # The controller also creates security groups (the ALB SG + the shared k8s-traffic-*
      # backend SG) OUTSIDE Terraform state. If any survive the ingress deletion they block
      # VPC teardown with DependencyViolation. Sweep by the controller's cluster tag.
      for sg in $(aws ec2 describe-security-groups --region ${self.triggers.region} ${self.triggers.profile != "" ? "--profile ${self.triggers.profile}" : ""} --filters "Name=tag:elbv2.k8s.aws/cluster,Values=${self.triggers.cluster}" --query 'SecurityGroups[].GroupId' --output text 2>/dev/null); do
        aws ec2 delete-security-group --region ${self.triggers.region} ${self.triggers.profile != "" ? "--profile ${self.triggers.profile}" : ""} --group-id "$sg" 2>/dev/null || true
      done
    EOT
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}
