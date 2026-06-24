# Karpenter platform IAM/SQS via the official EKS module's karpenter submodule.
# Uses EKS Pod Identity (the cluster already runs the eks-pod-identity-agent addon),
# so no IRSA service-account annotation is needed — the submodule creates the
# pod identity association for the `karpenter` service account in kube-system.
#
# Creates: controller IAM role + scoped policy, node IAM role + instance profile,
# an EKS access entry for the node role, and the SQS interruption queue + rules.

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  # The Karpenter controller policy exceeds the 6,144-char managed-policy quota.
  # Inline policies allow up to 10,240 chars, which fits. (Module's documented fix.)
  enable_inline_policy = true

  # Pod Identity association (default true) — the cluster runs the pod-identity
  # agent, so the controller gets IAM via this association (no IRSA needed).
  create_pod_identity_association = true
  namespace                       = "kube-system"
  service_account                 = "karpenter"

  # Stable, predictable node role name (referenced by the EC2NodeClass).
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "petclinic-karpenter-node"
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Project   = "petclinic"
    Environment = "production"
    ManagedBy = "terraform"
  }
}

output "karpenter_queue_name" {
  description = "SQS interruption queue — pass to the Karpenter Helm chart (settings.interruptionQueue)."
  value       = module.karpenter.queue_name
}

output "karpenter_node_iam_role_name" {
  description = "Node IAM role name — referenced by the EC2NodeClass spec.role."
  value       = module.karpenter.node_iam_role_name
}
