module "clusterautoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 4.15"

  role_name                        = "clusterautoscaler-${local.name}"
  attach_cluster_autoscaler_policy = true

  cluster_autoscaler_cluster_ids = [module.eks.cluster_id]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-cluster-autoscaler"]
    }
  }
}
