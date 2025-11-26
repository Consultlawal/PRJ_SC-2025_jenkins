locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.demo_node.arn}
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
  value       = local.kubeconfig
  sensitive = true # Recommended for kubeconfig output
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

# The following outputs were previously commented out in your provided outputs.tf
# If you actually need them, ensure the corresponding resources are defined.
# output "github_actions_user_access_key_create" {
#    value = "Create access key in console for user ${aws_iam_user.github_actions_user.name} if you don't use OIDC"
# }

# output "github_actions_oidc_provider_arn" {
#    value = aws_iam_openid_connect_provider.github_actions.arn
# }