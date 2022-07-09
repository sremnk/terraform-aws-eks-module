terraform {
  required_version = "= 1.2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 4.16.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.4"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "= 1.14"
    }
  }
}
