module "vpc" {
  source = "../../modules/vpc"

  vpc_name = "petclinic-prod"

  vpc_cidr = "10.0.0.0/16"

  public_subnet_a = "10.0.1.0/24"
  public_subnet_b = "10.0.2.0/24"

  private_subnet_a = "10.0.10.0/24"
  private_subnet_b = "10.0.20.0/24"

  az_a = "eu-central-1a"
  az_b = "eu-central-1b"
}

module "eks" {
  source = "../../modules/eks"

  cluster_name    = "petclinic-prod"
  cluster_version = "1.33"

  vpc_id = module.vpc.vpc_id

  private_subnet_ids = module.vpc.private_subnet_ids
}

module "iam" {
  source = "../../modules/iam"

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}

module "ecr" {
  source = "../../modules/ecr"

  repository_names = [
    "petclinic-config-server",
    "petclinic-discovery-server",
    "petclinic-customers-service",
    "petclinic-visits-service",
    "petclinic-vets-service",
    "petclinic-api-gateway",
    "petclinic-admin-server"
  ]
}