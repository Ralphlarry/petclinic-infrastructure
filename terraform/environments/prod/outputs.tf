output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "aws_region" {
  value = var.aws_region
}

output "alb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller (used by the addons bootstrap)."
  value       = module.iam.alb_controller_role_arn
}
