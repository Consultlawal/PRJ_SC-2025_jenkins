#
# EKS Worker Nodes Resources
# Keypair, IAM Roles, Autoscaling Policies, Node Group
#

#---------------------------------------------
# 1. TLS Keypair (RSA 4096)
#---------------------------------------------
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.key.private_key_pem
  filename        = "${var.cluster_name}-key.pem"
  file_permission = "400"
}

resource "aws_key_pair" "public_key" {
  key_name   = "${var.cluster_name}-public-key"
  public_key = tls_private_key.key.public_key_openssh
}

#---------------------------------------------
# 2. IAM Role for Worker Nodes
#---------------------------------------------
resource "aws_iam_role" "demo_node" {
  name = "${var.cluster_name}-worker-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

# Attach AWS managed EKS policies
resource "aws_iam_role_policy_attachment" "worker_eks" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.demo_node.name
}

resource "aws_iam_role_policy_attachment" "worker_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.demo_node.name
}

resource "aws_iam_role_policy_attachment" "worker_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.demo_node.name
}

#---------------------------------------------
# 3. Autoscaler IAM Policy
#---------------------------------------------
data "aws_iam_policy_document" "worker_autoscaling" {
  statement {
    sid    = "AllAutoscalingRead"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AutoscalingWriteForOwnedNodes"
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }
  }
}

resource "aws_iam_policy" "worker_autoscaling" {
  name        = "${var.cluster_name}-worker-autoscaling"
  description = "Autoscaling policy for EKS worker nodes"
  policy      = data.aws_iam_policy_document.worker_autoscaling.json
}

resource "aws_iam_role_policy_attachment" "workers_autoscaling" {
  policy_arn = aws_iam_policy.worker_autoscaling.arn
  role       = aws_iam_role.demo_node.name
}

#---------------------------------------------
# 4. Optional SSM Access
#---------------------------------------------
resource "aws_iam_role" "prod_ssm_role" {
  name = "${var.cluster_name}-prod-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

#---------------------------------------------
# 5. EKS Node Group
#---------------------------------------------
resource "aws_eks_node_group" "demo" {
  cluster_name    = aws_eks_cluster.demo.name
  node_group_name = "demo"
  node_role_arn   = aws_iam_role.demo_node.arn
  subnet_ids      = aws_subnet.demo[*].id
  instance_types  = [var.eks_node_instance_type]

  remote_access {
    ec2_ssh_key = aws_key_pair.public_key.key_name
  }

  tags = {
    "eks.amazonaws.com/nodegroup"    = "demo"
    "eks.amazonaws.com/cluster-name" = var.cluster_name
  }

  scaling_config {
    desired_size = 2
    max_size     = 200
    min_size     = 2
  }

  depends_on = [
    aws_iam_role_policy_attachment.worker_eks,
    aws_iam_role_policy_attachment.worker_cni,
    aws_iam_role_policy_attachment.worker_ecr,
    aws_iam_role_policy_attachment.workers_autoscaling
  ]
}
