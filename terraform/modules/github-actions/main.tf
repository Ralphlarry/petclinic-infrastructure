data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"

      identifiers = [
        "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
      ]
    }

    condition {
      test = "StringEquals"

      variable = "token.actions.githubusercontent.com:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test = "StringLike"

      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:${var.github_owner}/${var.github_repo}:*"
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {

  name = "GitHubActionsPetclinicRole"

  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# REMOVED: AmazonEKSClusterPolicy. That AWS-managed policy is for the EKS
# control-plane service role and grants the CI principal nothing useful for
# kubectl (in-cluster access is governed by EKS access entries / aws-auth).
# Under the Argo CD model, CI doesn't touch the cluster at all (ECR push only).