// In terraform/autoscaler-irsa.tf


// 1. Policy Document for the Cluster Autoscaler Service Account (SA)
data "aws_iam_policy_document" "autoscaler_assume" {
  statement {
    effect  = "Allow"
    principals {
      // Reference the OIDC issuer from the EKS cluster data
      identifiers = [data.aws_eks_cluster.demo.identity[0].oidc[0].issuer]
      type        = "Federated"
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      // Service Account name for the Cluster Autoscaler (namespace:kube-system, name:cluster-autoscaler)
      variable = "${replace(data.aws_eks_cluster.demo.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
  }
}

// 2. Cluster Autoscaler IAM Role
resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${var.cluster_name}-ClusterAutoscaler-Role"
  assume_role_policy = data.aws_iam_policy_document.autoscaler_assume.json
}

// 3. Attach AWS Managed Policy (The standard EKS policy for the autoscaler)
resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterAutoscalerPolicy"
}

// --- Outputs ---
output "autoscaler_iam_role_arn" {
  description = "The ARN of the IAM role for the Cluster Autoscaler."
  value       = aws_iam_role.cluster_autoscaler.arn // <-- FIXED NAME HERE
}
