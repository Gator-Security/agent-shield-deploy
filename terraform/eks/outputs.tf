output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS region."
  value       = var.region
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}${var.aws_profile != "" ? " --profile ${var.aws_profile}" : ""}"
}

output "console_url" {
  description = "Public console URL (ALB DNS). HTTPS if an ACM cert was supplied, else HTTP."
  value       = try("${var.acm_certificate_arn != "" ? "https" : "http"}://${kubernetes_ingress_v1.console.status[0].load_balancer[0].ingress[0].hostname}", "(ALB provisioning — re-run `terraform output` in a minute)")
}

output "db_endpoint" {
  description = "RDS Postgres endpoint (private)."
  value       = aws_db_instance.this.address
}

output "namespace" {
  description = "Namespace the control plane is installed into."
  value       = var.namespace
}

output "image_prefix" {
  description = "Resolved image prefix the chart pulls from."
  value       = local.image_prefix
}
