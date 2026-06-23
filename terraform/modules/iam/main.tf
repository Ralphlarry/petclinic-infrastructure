data "aws_iam_policy_document" "alb_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Create the ALB controller policy from the bundled JSON instead of referencing a
# hardcoded, pre-existing ARN (which fails on a clean account and pins the account id).
# NOTE: if AWSLoadBalancerControllerIAMPolicy already exists, import it first:
#   terraform import module.iam.aws_iam_policy.alb_controller \
#     arn:aws:iam::<account>:policy/AWSLoadBalancerControllerIAMPolicy
resource "aws_iam_policy" "alb_controller" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = file("${path.module}/iam_policy.json")

  tags = {
    Project   = "petclinic"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "AmazonEKSLoadBalancerControllerRole"
  assume_role_policy = data.aws_iam_policy_document.alb_assume_role.json

  tags = {
    Project   = "petclinic"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}