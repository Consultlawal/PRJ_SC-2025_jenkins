# --- Common IRSA Setup (Required by ALL EKS Service Account Roles) ---

# Defines the trust policy that allows a Kubernetes Service Account (SA) 
# to assume this role based on the EKS OIDC provider.
data "aws_iam_policy_document" "assume_role_sa" {
  statement {
    effect  = "Allow"
    principals {
      identifiers = [aws_eks_cluster.demo.identity[0].oidc[0].issuer]
      type        = "Federated"
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      # The Service Account name for the ALB Controller will be 'aws-load-balancer-controller'
      variable = "${replace(aws_eks_cluster.demo.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

# --- ALB Controller IRSA Resources ---

# 1. IAM Role for ALB Controller Service Account
resource "aws_iam_role" "alb_controller" {
  # Variable used for naming
  name               = "${var.cluster_name}-ALBController-Role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_sa.json

  # CRITICAL: Wait for the EKS Cluster to exist and have its OIDC identity ready
  depends_on = [
    aws_eks_cluster.demo,
    # data.aws_iam_openid_connect_provider.eks_oidc_provider
  ]
}

# 2. Attach AWS Managed Policy (Recommended by AWS)
resource "aws_iam_role_policy_attachment" "alb_controller_attach_managed" {
  role       = aws_iam_role.alb_controller.name
  # The official AWS managed policy for the Load Balancer Controller
  policy_arn = "arn:aws:iam::aws:policy/AWSLoadBalancerControllerIAMPolicy"
}

