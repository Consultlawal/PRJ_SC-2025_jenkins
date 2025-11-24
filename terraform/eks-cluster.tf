# #
# # EKS Cluster Resources
# #  * IAM Role to allow EKS service to manage other AWS services
# #  * EC2 Security Group to allow networking traffic with EKS cluster
# #  * EKS Cluster
# #

# resource "aws_iam_role" "demo-cluster" {
#   name = "terraform-eks-demo-cluster"

#   assume_role_policy = <<POLICY
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Effect": "Allow",
#       "Principal": {
#         "Service": "eks.amazonaws.com"
#       },
#       "Action": "sts:AssumeRole"
#     }
#   ]
# }
# POLICY
# }

# resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSClusterPolicy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
#   role       = aws_iam_role.demo-cluster.name
# }

# resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSServicePolicy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
#   role       = aws_iam_role.demo-cluster.name
# }

# resource "aws_security_group" "demo-cluster" {
#   name        = "terraform-eks-demo-cluster"
#   description = "Cluster communication with worker nodes"
#   vpc_id      = aws_vpc.demo.id

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name = "terraform-eks-demo"
#   }
# }

# resource "aws_security_group_rule" "demo-cluster-ingress-workstation-https" {
#   cidr_blocks       = ["0.0.0.0/0"] # Open for Demo/CI access. For prod, use VPN.
#   description       = "Allow internet to communicate with the cluster API Server"
#   from_port         = 443
#   protocol          = "tcp"
#   security_group_id = aws_security_group.demo-cluster.id
#   to_port           = 443
#   type              = "ingress"
# }

# # ----------------------------------------------------------------------
# # CRITICAL FIX for NodeCreationFailure
# # This rule allows all traffic from the entire VPC CIDR to the EKS 
# # Control Plane on port 443, which resolves the dependency issue by 
# # guaranteeing connectivity for newly launched worker nodes.
# # ----------------------------------------------------------------------
# resource "aws_security_group_rule" "temp_cluster_ingress_443_from_vpc" {
#   type              = "ingress"
#   from_port         = 443
#   to_port           = 443
#   protocol          = "tcp"
#   cidr_blocks       = [aws_vpc.demo.cidr_block]
#   security_group_id = aws_security_group.demo-cluster.id
#   description       = "FIX: Allow EKS nodes (from VPC CIDR) to talk to the Control Plane on 443."
# }

# resource "aws_eks_cluster" "demo" {
#   name     = var.cluster_name
#   role_arn = aws_iam_role.demo-cluster.arn

#   vpc_config {
#     security_group_ids = [aws_security_group.demo-cluster.id]
#     subnet_ids         = aws_subnet.demo[*].id
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.demo-cluster-AmazonEKSClusterPolicy,
#     aws_iam_role_policy_attachment.demo-cluster-AmazonEKSServicePolicy,
#     # Adding the SG rule here ensures it exists before the cluster is active
#     aws_security_group_rule.temp_cluster_ingress_443_from_vpc
#   ]
# }

# # Add this to one of your .tf files in the terraform directory, e.g., eks-cluster.tf
# # This resource links the EKS cluster's OIDC issuer to IAM
# resource "aws_iam_openid_connect_provider" "demo" {
#   client_id_list = ["sts.amazonaws.com"]
#   thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
#   url            = aws_eks_cluster.demo.identity[0].oidc[0].issuer
# }

# # This data source is required to get the OIDC provider's thumbprint
# data "tls_certificate" "oidc" {
#   url = aws_eks_cluster.demo.identity[0].oidc[0].issuer
# }

# # NEW: Data source to explicitly reference the OIDC provider created by EKS
# # data "aws_iam_openid_connect_provider" "eks_oidc_provider" {
# #   url = aws_eks_cluster.demo.identity[0].oidc[0].issuer
  
# #   # Ensure the data source lookup waits for the cluster resource to be available
# #   depends_on = [
# #     aws_eks_cluster.demo
# #   ]
# # }



# #
# # EKS Cluster Resources (corrected IRSA / OIDC integration)
# #

# resource "aws_iam_role" "demo-cluster" {
#   name = "terraform-eks-demo-cluster"

#   assume_role_policy = <<POLICY
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Effect": "Allow",
#       "Principal": {
#         "Service": "eks.amazonaws.com"
#       },
#       "Action": "sts:AssumeRole"
#     }
#   ]
# }
# POLICY
# }

# resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSClusterPolicy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
#   role       = aws_iam_role.demo-cluster.name
# }

# resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSServicePolicy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
#   role       = aws_iam_role.demo-cluster.name
# }

# resource "aws_security_group" "demo-cluster" {
#   name        = "terraform-eks-demo-cluster"
#   description = "Cluster communication with worker nodes"
#   vpc_id      = aws_vpc.demo.id

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name = "terraform-eks-demo"
#   }
# }

# resource "aws_security_group_rule" "demo-cluster-ingress-workstation-https" {
#   cidr_blocks       = ["0.0.0.0/0"]
#   description       = "Allow internet to communicate with the cluster API Server"
#   from_port         = 443
#   protocol          = "tcp"
#   security_group_id = aws_security_group.demo-cluster.id
#   to_port           = 443
#   type              = "ingress"
# }

# # Temporary (or permanent depending on your network design) rule to allow nodes in VPC to talk to control plane
# resource "aws_security_group_rule" "temp_cluster_ingress_443_from_vpc" {
#   type              = "ingress"
#   from_port         = 443
#   to_port           = 443
#   protocol          = "tcp"
#   cidr_blocks       = [aws_vpc.demo.cidr_block]
#   security_group_id = aws_security_group.demo-cluster.id
#   description       = "Allow EKS nodes (from VPC CIDR) to talk to the Control Plane on 443."
# }

# resource "aws_eks_cluster" "demo" {
#   name     = var.cluster-name
#   role_arn = aws_iam_role.demo-cluster.arn

#   vpc_config {
#     security_group_ids = [aws_security_group.demo-cluster.id]
#     subnet_ids         = aws_subnet.demo[*].id
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.demo-cluster-AmazonEKSClusterPolicy,
#     aws_iam_role_policy_attachment.demo-cluster-AmazonEKSServicePolicy,
#     aws_security_group_rule.temp_cluster_ingress_443_from_vpc,
#   ]
# }

# # Get the TLS certificate fingerprint for the EKS OIDC issuer so we can create the IAM OIDC provider
# data "tls_certificate" "oidc" {
#   url = aws_eks_cluster.demo.identity[0].oidc[0].issuer
#   # depend implicitly on the cluster
#   depends_on = [aws_eks_cluster.demo]
# }

# # Create the IAM OIDC provider for EKS (so IRSA roles can reference its ARN)
# resource "aws_iam_openid_connect_provider" "demo" {
#   client_id_list  = ["sts.amazonaws.com"]
#   thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
#   url             = aws_eks_cluster.demo.identity[0].oidc[0].issuer

#   depends_on = [aws_eks_cluster.demo]
# }


resource "aws_iam_role" "demo-cluster" {
  name = "terraform-eks-demo-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.demo-cluster.name
}

resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.demo-cluster.name
}

resource "aws_security_group" "demo-cluster" {
  name        = "terraform-eks-demo-cluster"
  description = "Cluster communication with worker nodes"
  vpc_id      = aws_vpc.demo.id

  # This allows all egress traffic, which is typically desired for EKS control plane and nodes
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-eks-demo"
  }
}

resource "aws_security_group_rule" "demo-cluster-ingress-workstation-https" {
  # This rule allows access to the EKS API server from anywhere.
  # For production, restrict cidr_blocks to your trusted network IPs.
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow internet to communicate with the cluster API Server"
  from_port         = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.demo-cluster.id
  to_port           = 443
  type              = "ingress"
}

# Critical for Node Joining: Allow EKS nodes (from VPC CIDR) to talk to the Control Plane on 443.
# This prevents 'NodeCreationFailure: Instances failed to join the kubernetes cluster'
resource "aws_security_group_rule" "temp_cluster_ingress_443_from_vpc" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.demo.cidr_block] # Ensure this matches your VPC CIDR
  security_group_id = aws_security_group.demo-cluster.id
  description       = "Allow EKS nodes (from VPC CIDR) to talk to the Control Plane on 443."
}

resource "aws_eks_cluster" "demo" {
  name     = var.cluster-name # Keeping var.cluster-name
  role_arn = aws_iam_role.demo-cluster.arn

  vpc_config {
    security_group_ids = [aws_security_group.demo-cluster.id]
    # Ensure aws_subnet.demo[*] correctly refers to your VPC subnets (public and/or private)
    subnet_ids         = aws_subnet.demo[*].id
    # Consider enabling public_access_cidrs for EKS API endpoint if you restricted earlier.
    # public_access_cidrs = ["0.0.0.0/0"] 
  }

  # Ensure the cluster is ready for OIDC, Security Groups, and IAM roles are attached
  depends_on = [
    aws_iam_role_policy_attachment.demo-cluster-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.demo-cluster-AmazonEKSServicePolicy,
    aws_security_group_rule.temp_cluster_ingress_443_from_vpc,
  ]

  # Required for the OIDC provider to be available immediately after cluster creation
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# Get the TLS certificate fingerprint for the EKS OIDC issuer.
# This must explicitly depend on the OIDC issuer URL being available from the cluster.
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.demo.identity[0].oidc[0].issuer
  # Explicit dependency to ensure the cluster's OIDC issuer is fully formed.
  # Terraform implicitly handles this for attribute references but explicit can help.
  depends_on = [aws_eks_cluster.demo]
}

# Create the IAM OIDC provider for EKS (so IRSA roles can reference its ARN).
# This is crucial for the IRSA roles to assume their service accounts.
resource "aws_iam_openid_connect_provider" "demo" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.demo.identity[0].oidc[0].issuer

  # This depends_on ensures the cluster is fully up and the TLS certificate data is fetched.
  # This is the key to preventing "MalformedPolicyDocument" for IRSA roles.
  depends_on = [
    aws_eks_cluster.demo,
    data.tls_certificate.oidc # Explicitly depend on the data source being resolved
  ]
}