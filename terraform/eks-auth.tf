# --- EKS aws-auth ConfigMap for Worker Nodes and GitHub Actions Role ---
# This resource configures the `aws-auth` ConfigMap in the `kube-system` namespace.
# It maps AWS IAM roles to Kubernetes users and groups, allowing those roles
# to authenticate and authorize against the EKS cluster API.
# Place this in a new file like 'eks-auth.tf' or within your main Terraform configuration.

resource "kubernetes_config_map_v1" "aws_auth_map" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    # mapRoles defines the mapping of IAM roles to Kubernetes groups.
    mapRoles = yamlencode([
      # 1. Mapping for EKS Worker Node Role:
      # This entry allows the EC2 instances in your EKS node groups
      # to join the cluster. The `system:bootstrappers` and `system:nodes`
      # groups are standard for worker nodes.
      {
        rolearn  = aws_iam_role.demo_node.arn # This comes from your eks-worker-nodes.tf
        username = "system:node:{{EC2PrivateDNSName}}" # Dynamic username for each node
        groups = [
          "system:bootstrappers", # Required for node bootstrapping
          "system:nodes",         # Required for node operations in Kubernetes
        ]
      },
      # 2. Mapping for GitHub Actions IAM Role:
      # This entry grants your GitHub Actions OIDC role access to the EKS cluster.
      # By mapping it to "system:masters", it gets full administrative access,
      # which is necessary for the CI/CD pipeline to deploy and manage resources.
      {
        rolearn  = aws_iam_role.github_actions.arn # This is the IAM role you created for GitHub Actions OIDC
        username = "github-actions-user"           # A descriptive username for logging purposes
        groups   = [
          "system:masters", # Grants full administrative access to the cluster
        ]
      }
    ])
  }

  # Explicit dependencies ensure that the referenced AWS and Kubernetes resources
  # are fully provisioned before Terraform attempts to create or update this ConfigMap.
  # This prevents errors where the ConfigMap tries to reference non-existent roles or clusters.
  depends_on = [
    aws_eks_cluster.demo,          # Ensure the EKS cluster itself is fully provisioned
    aws_iam_role.demo_node,        # Ensure the worker node IAM role is created
    aws_iam_role.github_actions,   # Ensure the GitHub Actions IAM role is created (from your other .tf file)
  ]
}