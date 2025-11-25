# # ./terraform/outputs.tf
# #
# # Consolidated Outputs for the EKS Cluster and related components
# # This file should contain ALL output definitions for the root Terraform module.
# #

# locals {
#   config_map_aws_auth = <<CONFIGMAPAWSAUTH
# apiVersion: v1
# kind: ConfigMap
# metadata:
#   name: aws-auth
#   namespace: kube-system
# data:
#   mapRoles: |
#     - rolearn: ${aws_iam_role.demo-node.arn}
#       username: system:node:{{EC2PrivateDNSName}}
#       groups:
#         - system:bootstrappers
#         - system:nodes
# CONFIGMAPAWSAUTH

#   kubeconfig = <<KUBECONFIG
# apiVersion: v1
# clusters:
# - cluster:
#     server: ${aws_eks_cluster.demo.endpoint}
#     certificate-authority-data: ${aws_eks_cluster.demo.certificate_authority.0.data}
#   name: kubernetes
# contexts:
# - context:
#     cluster: kubernetes
#     user: aws
#   name: aws
# current-context: aws
# kind: Config
# preferences: {}
# users:
# - name: aws
#   user:
#     exec:
#       apiVersion: client.authentication.k8s.io/v1beta1
#       command: aws
#       args:
#         - "eks"
#         - "get-token"
#         - "--cluster-name"
#         - "${var.cluster_name}"
# KUBECONFIG
# }

# output "config_map_aws_auth" {
#   description = "Kubernetes ConfigMap for aws-auth to map node roles."
#   value       = local.config_map_aws_auth
# }

# output "kubeconfig" {
#   description = "Generated Kubeconfig for the EKS cluster."
#   value       = local.kubeconfig
#   sensitive   = true # Kubeconfig contains sensitive information
# }

# output "subnet_public" {
#   description = "Indicates if public subnets map public IPs on launch."
#   # Assuming aws_subnet.demo is a list/map, adjust index if needed.
#   # If you have specific public/private subnets, you might reference e.g., aws_subnet.public_subnet_a.map_public_ip_on_launch
#   value       = aws_subnet.demo[0].map_public_ip_on_launch
# }

# output "eks_oidc_issuer_url" {
#   description = "The URL of the EKS cluster's OIDC Identity provider."
#   value       = aws_eks_cluster.demo.identity[0].oidc[0].issuer
# }

# output "eks_oidc_provider_arn" {
#   description = "The ARN of the EKS cluster's OIDC Identity provider."
#   value       = aws_iam_openid_connect_provider.demo.arn
# }

# output "alb_controller_role_arn" {
#   description = "ARN of the IAM role for the AWS Load Balancer Controller."
#   value       = aws_iam_role.alb_controller.arn
# }

# output "external_dns_role_arn" {
#   description = "ARN of the IAM role for ExternalDNS."
#   value       = aws_iam_role.external_dns.arn
# }

# output "autoscaler_iam_role_arn" {
#   description = "ARN of the IAM role for the Cluster Autoscaler."
#   value       = aws_iam_role.cluster_autoscaler.arn
# }

# output "ci_artifacts_bucket" {
#   description = "Name of the S3 bucket for CI artifacts."
#   value       = aws_s3_bucket.ci_artifacts.bucket
# }

# output "github_actions_user_access_key_create" {
#   description = "Instruction for IAM user access key (if not using OIDC)."
#   value       = "Create access key in console for user ${aws_iam_user.github_actions_user.name} and store as GitHub secret if you don't use OIDC"
# }

# # Output the ARN of the GitHub Actions OIDC provider.
# # This ARN is required when configuring the trust policy for the IAM role
# # that your GitHub Actions workflow will assume.
# output "github_actions_oidc_provider_arn" {
#   description = "The ARN of the AWS IAM OIDC Provider for GitHub Actions."
#   value       = aws_iam_openid_connect_provider.github_actions.arn
# }

locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.demo-node.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
CONFIGMAPAWSAUTH

  kubeconfig = <<KUBECONFIG
apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.demo.endpoint}
    certificate-authority-data: ${aws_eks_cluster.demo.certificate_authority[0].data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws
      args:
        - eks
        - get-token
        - --cluster-name
        - ${var.cluster_name}
KUBECONFIG
}

output "config_map_aws_auth" {
  value = local.config_map_aws_auth
}

output "kubeconfig" {
  value     = local.kubeconfig
  sensitive = true
}

output "subnet_public" {
  value = aws_subnet.demo[0].map_public_ip_on_launch
}

output "eks_oidc_issuer_url" {
  value = aws_eks_cluster.demo.identity[0].oidc[0].issuer
}

output "eks_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.demo.arn
}

output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}

output "external_dns_role_arn" {
  value = aws_iam_role.external_dns.arn
}

output "autoscaler_iam_role_arn" {
  value = aws_iam_role.cluster_autoscaler.arn
}

output "ci_artifacts_bucket" {
  value = aws_s3_bucket.ci_artifacts.bucket
}

# output "github_actions_user_access_key_create" {
#   value = "Create access key in console for user ${aws_iam_user.github_actions_user.name} if you don't use OIDC"
# }

output "github_actions_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github_actions.arn
}
