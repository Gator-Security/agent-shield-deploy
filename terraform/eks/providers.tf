# The kubernetes/helm providers authenticate to the freshly-created EKS cluster with a
# short-lived token minted by the AWS CLI exec plugin (robust across long applies — no
# baked-in token that can expire mid-run). Requires the `aws` CLI on the apply host.
provider "aws" {
  region  = var.region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = local.tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = concat(
      ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region],
      var.aws_profile != "" ? ["--profile", var.aws_profile] : [],
    )
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = concat(
        ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region],
        var.aws_profile != "" ? ["--profile", var.aws_profile] : [],
      )
    }
  }
}
