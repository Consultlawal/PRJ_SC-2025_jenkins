# --- Data Source for GitHub Actions OIDC Provider ---
# This data source directly references the known GitHub OIDC provider ARN.
data "aws_iam_openid_connect_provider" "github" {
  arn = "arn:aws:iam::009593259890:oidc-provider/token.actions.githubusercontent.com"
}

# --- IAM Role for GitHub Actions Workflow ---
# This role is assumed by your GitHub Actions runner to perform Terraform operations
# and interact with AWS services like EKS, EC2, etc.
resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
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

# --- IAM Policy for GitHub Actions Workflow ---
# This policy grants the necessary permissions for the GitHub Actions role
# to manage EKS, EC2, IAM, SSM, STS, CloudFormation, and potentially S3/Logs
# if the runner itself needs to interact with them directly.
resource "aws_iam_role_policy" "github_actions_policy" {
  role = aws_iam_role.github_actions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:*",
          "ec2:*",
          "iam:*",
          "ssm:*",
          "sts:*",
          "cloudformation:*",
          "s3:*",  # Potentially needed if GitHub Actions runner itself performs S3 operations
          "logs:*" # Potentially needed if GitHub Actions runner itself performs CloudWatch Logs operations
        ]
        Resource = "*" # Consider scoping this down for production environments
      }
    ]
  })
}


# --- NEW: IAM Policy for Falco (IRSA) ---
# This policy defines the AWS permissions that Falco will have when running in EKS.
# Example: Sending logs to CloudWatch Logs and S3.
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
        Resource = "arn:aws:logs:*:*:*" # Can be restricted to specific log groups
      },
      { # IMPORTANT: REPLACE 'your-falco-alerts-bucket-name' WITH YOUR ACTUAL S3 BUCKET NAME
        # If Falco does NOT need S3 access, remove this entire 'Statement' block.
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

  tags = {
    Name        = "FalcoCloudWatchLogsS3Policy-${var.cluster_name}"
    Environment = var.environment
    Project     = "SecurityMesh"
  }
}


# --- NEW: Data Source to get EKS Cluster details for OIDC Issuer ---
# This looks up your existing EKS cluster resource by its name.
data "aws_eks_cluster" "current_eks_cluster" {
  name = var.cluster_name
}

# --- NEW: Data Source to get the EKS OIDC Provider details ---
# This takes the OIDC issuer URL from the EKS cluster and looks up its ARN.
data "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url = data.aws_eks_cluster.current_eks_cluster.identity[0].oidc[0].issuer
}


# --- NEW: IAM Role for Falco Service Account (IRSA) ---
# This role is assumed by the 'falco' service account within the 'falco' namespace in EKS.
resource "aws_iam_role" "falco_role" {
  name_prefix = "falco-eks-role-" # Using name_prefix for uniqueness

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
            # Matches the OIDC issuer URL (without 'https://' prefix) and the K8s service account
            "${replace(data.aws_iam_openid_connect_provider.eks_oidc_provider.url, "https://", "")}:sub" = "system:serviceaccount:falco:falco"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "FalcoEKSRole-${var.cluster_name}"
    Environment = var.environment
    Project     = "SecurityMesh"
  }
}

# --- NEW: Attach the Falco policy to the Falco role ---
resource "aws_iam_role_policy_attachment" "falco_policy_attach" {
  role       = aws_iam_role.falco_role.name
  policy_arn = aws_iam_policy.falco_policy.arn
}


# --- Output for GitHub Secrets ---
# The ARN of the GitHub Actions role
output "github_actions_role_arn" {
  description = "ARN of the IAM Role for GitHub Actions (for GH_ACTIONS_ROLE_ARN secret)"
  value       = aws_iam_role.github_actions.arn
}

# The ARN of the Falco IRSA role
output "falco_irsa_role_arn" {
  description = "ARN of the IAM Role for Falco Service Account (for FALCO_IRSA_ROLE_ARN secret)"
  value       = aws_iam_role.falco_role.arn
}