
################################################################################
# Karpenter
################################################################################

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_id]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_id]
  }
}

module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 4.15"

  role_name                          = "karpenter-controller-${local.name}"
  attach_karpenter_controller_policy = true

  karpenter_controller_cluster_id = module.eks.cluster_id
  karpenter_controller_node_iam_role_arns = [
    module.eks.eks_managed_node_groups["karpenter"].iam_role_arn
  ]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile-${local.name}"
  role = module.eks.eks_managed_node_groups["karpenter"].iam_role_name
}

# resource "helm_release" "karpenter" {
#   namespace        = "karpenter"
#   create_namespace = true

#   name       = "karpenter"
#   repository = "https://charts.karpenter.sh"
#   chart      = "karpenter"
#   version    = "0.8.1"

#   set {
#     name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#     value = module.karpenter_irsa.iam_role_arn
#   }

#   set {
#     name  = "clusterName"
#     value = module.eks.cluster_id
#   }

#   set {
#     name  = "clusterEndpoint"
#     value = module.eks.cluster_endpoint
#   }

#   set {
#     name  = "aws.defaultInstanceProfile"
#     value = aws_iam_instance_profile.karpenter.name
#   }
# }

# # Workaround - https://github.com/hashicorp/terraform-provider-kubernetes/issues/1380#issuecomment-967022975
# resource "kubectl_manifest" "karpenter_provisioner" {
#   yaml_body = <<-YAML
#   apiVersion: karpenter.sh/v1alpha5
#   kind: Provisioner
#   metadata:
#     name: default
#   spec:
#     requirements:
#       - key: karpenter.sh/capacity-type
#         operator: In
#         values: ["spot"]
#     limits:
#       resources:
#         cpu: 1000
#     provider:
#       subnetSelector:
#         karpenter.sh/discovery: ${local.name}
#       securityGroupSelector:
#         karpenter.sh/discovery: ${local.name}
#       tags:
#         karpenter.sh/discovery: ${local.name}
#     ttlSecondsAfterEmpty: 30
#   YAML

#   depends_on = [
#     helm_release.karpenter
#   ]
# }

# # Example deployment using the [pause image](https://www.ianlewis.org/en/almighty-pause-container)
# # and starts with zero replicas
# resource "kubectl_manifest" "karpenter_example_deployment" {
#   yaml_body = <<-YAML
#   apiVersion: apps/v1
#   kind: Deployment
#   metadata:
#     name: inflate
#   spec:
#     replicas: 0
#     selector:
#       matchLabels:
#         app: inflate
#     template:
#       metadata:
#         labels:
#           app: inflate
#       spec:
#         terminationGracePeriodSeconds: 0
#         containers:
#           - name: inflate
#             image: public.ecr.aws/eks-distro/kubernetes/pause:3.2
#             resources:
#               requests:
#                 cpu: 1
#   YAML

#   depends_on = [
#     helm_release.karpenter
#   ]
# }
