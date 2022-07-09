

data "aws_eks_cluster_auth" "default" {
  name = local.name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.default.token

  # exec {
  #   api_version = "client.authentication.k8s.io/v1alpha1"
  #   command     = "aws"
  #   # This requires the awscli to be installed locally where Terraform is executed
  #   args = ["eks", "get-token", "--cluster-name", module.eks.cluster_id]
  # }
}

locals {
  name            = var.eks_cluster_name
  cluster_version = var.eks_cluster_version

  tags = var.common_tags
}


data "aws_caller_identity" "current" {}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "= 18.23.0"

  cluster_name    = local.name
  cluster_version = local.cluster_version

  cluster_endpoint_private_access = false
  cluster_endpoint_public_access  = true

  cluster_addons = {
    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {}
    vpc-cni = {
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
    }
  }

  cluster_encryption_config = [{
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }]

  cluster_tags = {
    Name                                  = local.name
    "kubernetes.io/cluster/${local.name}" = local.name
  }

  node_security_group_tags = {
    "kubernetes.io/cluster/${local.name}" = null
  }
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Extend cluster security group rules
  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

  # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    },
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }


  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    disk_size      = var.workernode_disk_size
    instance_types = var.workernode_instance_types
    key_name       = aws_key_pair.this.id

    # We are using the IRSA created below for permissions
    # However, we have to deploy with the policy attached FIRST (when creating a fresh cluster)
    # and then turn this off after the cluster/node group is created. Without this initial policy,
    # the VPC CNI fails to assign IPs and nodes cannot join the cluster
    # See https://github.com/aws/containers-roadmap/issues/1666 for more context
    iam_role_attach_cni_policy = true

    tags = merge(local.tags, {
      "k8s.io/cluster-autoscaler/enabled"       = true
      "k8s.io/cluster-autoscaler/${local.name}" = true
      "kubernetes.io/cluster/${local.name}"     = "owned"
    })
  }


  eks_managed_node_groups = var.eks_managed_node_groups
  tags = merge(local.tags, {
  })

  # aws-auth configmap
  manage_aws_auth_configmap = true

  aws_auth_roles = var.aws_auth_roles

  aws_auth_users = var.aws_auth_users

}
resource "aws_iam_role_policy_attachment" "additional" {
  for_each = module.eks.eks_managed_node_groups

  policy_arn = aws_iam_policy.node_additional.arn
  role       = each.value.iam_role_name
}


resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.tags
}

resource "aws_ebs_encryption_by_default" "enabled" {
    enabled = true
}


resource "tls_private_key" "this" {
  algorithm = "RSA"
}

resource "aws_key_pair" "this" {
  key_name_prefix = local.name
  public_key      = tls_private_key.this.public_key_openssh

  tags = local.tags
}

resource "aws_secretsmanager_secret" "secret_key" {
  name_prefix = local.name
  description = "EKS worker node pem key"
  tags = merge(
    local.tags,
    { "Name" : "${local.name}-key" }
  )
}

resource "aws_secretsmanager_secret_version" "secret_key_value" {
  secret_id     = aws_secretsmanager_secret.secret_key.id
  secret_string = tls_private_key.this.private_key_pem
}

resource "aws_iam_policy" "node_additional" {
  name        = "${local.name}-additional"
  description = "Example usage of node additional policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })

  tags = local.tags
}
