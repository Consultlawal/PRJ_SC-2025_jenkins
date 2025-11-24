# ./terraform/github_actions_oidc_provider.tf
#
# This file defines the AWS IAM OIDC Provider for GitHub Actions.
# This is crucial for GitHub Actions workflows to assume IAM roles securely.
#

# Data source to fetch the TLS certificate thumbprint for GitHub's OIDC issuer.
# Note the "https://" prefix for the URL, which TLS certificate data source requires.
data "tls_certificate" "github_actions_oidc" {
  url = "https://token.actions.githubusercontent.com" # <--- CORRECT URL for GitHub Actions OIDC
}

# AWS IAM OpenID Connect Provider for GitHub Actions.
# This resource tells AWS IAM to trust identities issued by GitHub Actions.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions_oidc.certificates[0].sha1_fingerprint] # <--- CORRECT THUMBPRINT for GitHub Actions OIDC

  tags = {
    Name        = "github-actions-oidc-provider"
    ManagedBy   = "Terraform"
    Purpose     = "GitHub Actions OIDC Authentication"
  }
}