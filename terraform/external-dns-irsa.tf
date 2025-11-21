# --- ExternalDNS IRSA Resources ---

# 1. IAM Policy Document for ExternalDNS
# Defines the permissions required to modify Route 53 records.
data "aws_iam_policy_document" "external_dns_policy" {
  statement {
    effect  = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
      "route53:ListHostedZones"
    ]
    # Resources must be set to "*" as ExternalDNS manages all zones it's configured for.
    resources = ["*"]
  }
}

resource "aws_iam_policy" "external_dns" {
  # Variable used for naming
  name   = "${var.cluster_name}-ExternalDNS-Policy"
  policy = data.aws_iam_policy_document.external_dns_policy.json
}

# 2. Update the Assume Role Policy to target the ExternalDNS Service Account
data "aws_iam_policy_document" "external_dns_assume_role_sa" {
  statement {
    effect  = "Allow"
    principals {
      # References the OIDC issuer fetched from the EKS cluster
      identifiers = [aws_eks_cluster.demo.identity[0].oidc[0].issuer]
      type        = "Federated"
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      # The Service Account name for ExternalDNS will be 'external-dns'
      variable = "${replace(aws_eks_cluster.demo.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-dns:external-dns"]
    }
  }
}

# 3. IAM Role for ExternalDNS Service Account (Merged block with depends_on)
resource "aws_iam_role" "external_dns" {
  name               = "${var.cluster_name}-ExternalDNS-Role"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume_role_sa.json

  # CRITICAL: Wait for the EKS Cluster to exist and have its OIDC identity ready
  depends_on = [
    aws_eks_cluster.demo
  ]
}

# 4. Attach ExternalDNS Policy to Role
resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

# --- OUTPUTS (Crucial for the GitHub Actions Workflow) ---
output "external_dns_role_arn" {
  description = "ARN of the IAM role for ExternalDNS."
  value       = aws_iam_role.external_dns.arn
}