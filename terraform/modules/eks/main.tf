module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  endpoint_public_access  = true
  endpoint_private_access = true

  enable_irsa = true

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  addons = {
    vpc-cni = {
      before_compute = true
    }

    kube-proxy = {}

    coredns = {}

    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    petclinic_workers = {
      instance_types = ["t3.medium"]

      min_size     = 2
      desired_size = 2
      max_size     = 3

      capacity_type = "ON_DEMAND"

      subnet_ids = var.private_subnet_ids

      ami_type = "AL2023_x86_64_STANDARD"

      labels = {
        role = "application"
      }

      tags = {
        Name = "petclinic-workers"
      }
    }
  }

  enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = {
    Environment = "production"
    Project     = "petclinic"
    ManagedBy   = "terraform"
  }
}