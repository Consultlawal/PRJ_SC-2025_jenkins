#########################################
#  GITHUB OIDC PROVIDER (ALREADY EXISTS)
#########################################

data "aws_iam_openid_connect_provider" "github" {
  arn = "arn:aws:iam::009593259890:oidc-provider/token.actions.githubusercontent.com"
}

#########################################
#   IAM ROLE FOR GITHUB ACTIONS CI/CD
#########################################

resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "GitHubActionsTerraformRole-${var.cluster_name}"
    Environment = var.environment
    Project     = "SecurityMesh"
  }
}

resource "aws_iam_role_policy" "github_actions_policy" {
  role = aws_iam_role.github_actions.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "eks:*",
          "ec2:*",
          "iam:*",
          "ssm:*",
          "sts:*",
          "cloudformation:*",
          "s3:*",
          "logs:*"
        ],
        Resource = "*"
      }
    ]
  })
}

#########################################
#       EKS CLUSTER LOOKUP (FIXED)
#########################################

data "aws_eks_cluster" "current_eks_cluster" {
  name = aws_eks_cluster.demo.name
}

data "aws_eks_cluster_auth" "cluster_auth" {
  name = aws_eks_cluster.demo.name
}

#########################################
#   EKS OIDC PROVIDER LOOKUP (CORRECT)
#########################################

data "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url = data.aws_eks_cluster.current_eks_cluster.identity[0].oidc[0].issuer
}


#########################################
#          FALCO IAM POLICY
#########################################

resource "aws_iam_policy" "falco_policy" {
  name        = "FalcoCloudWatchLogsS3Policy-${var.cluster_name}"
  description = "IAM Policy for Falco to send alerts to CloudWatch Logs and S3"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:AbortMultipartUpload",
          "s3:DeleteObject"
        ],
        Resource = [
          "arn:aws:s3:::your-falco-alerts-bucket-name",
          "arn:aws:s3:::your-falco-alerts-bucket-name/*"
        ]
      }
    ]
  })
}

#########################################
#       FALCO IRSA ROLE (EKS TRUST)
#########################################

resource "aws_iam_role" "falco_role" {
  name_prefix = "falco-eks-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.eks_oidc_provider.arn
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.current_eks_cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:falco:falco"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "falco_policy_attach" {
  role       = aws_iam_role.falco_role.name
  policy_arn = aws_iam_policy.falco_policy.arn
}

#########################################
#              OUTPUTS
#########################################

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "falco_irsa_role_arn" {
  value = aws_iam_role.falco_role.arn
}
