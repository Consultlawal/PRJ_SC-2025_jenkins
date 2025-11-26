# --- ALB Controller IRSA ---

data "aws_iam_policy_document" "assume_role_alb" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.demo.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test      = "StringEquals"
      variable = "${replace(aws_eks_cluster.demo.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.cluster_name}-ALBController-Role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_alb.json

  depends_on = [
    aws_eks_cluster.demo,
    aws_iam_openid_connect_provider.demo
  ]
}

# resource "aws_iam_role_policy_attachment" "alb_controller_attach" {
#   role        = aws_iam_role.alb_controller.name
#   # CORRECTED: Changed to the correct AWS managed policy for the AWS Load Balancer Controller
#   policy_arn = "arn:aws:iam::aws:policy/AWSLoadBalancerControllerIAMPolicy"

#   depends_on = [aws_iam_role.alb_controller]
# }

# terraform/alb-controller-irsa.tf

# ... existing aws_iam_role.alb_controller ...

# IAM Policy for AWS Load Balancer Controller
# This policy is custom and needs to be created.
resource "aws_iam_policy" "alb_controller_policy" {
  name        = "${var.cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  path        = "/"
  description = "IAM policy for AWS Load Balancer Controller to manage ALBs, NLBs, and EC2 resources."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeClassicLinkInstances",
          "ec2:DescribeCoipPools",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeNetworkAcls",
          "ec2:DescribePublicIpv4Pools",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeVpcs",
          "ec2:AllocateAddress",
          "ec2:AssignPrivateIpAddresses",
          "ec2:AssociateAddress",
          "ec2:AssociateRouteTable",
          "ec2:AttachInternetGateway",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CopySnapshot",
          "ec2:CreateInternetGateway",
          "ec2:CreateSecurityGroup",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:DeleteInternetGateway",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteSnapshot",
          "ec2:DeleteTags",
          "ec2:DeleteVolume",
          "ec2:DeregisterInstancesFromLoadBalancer",
          "ec2:DetachInternetGateway",
          "ec2:DisassociateAddress",
          "ec2:DisassociateRouteTable",
          "ec2:GetLoadBalancerAttribute",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyLoadBalancerAttributes",
          "ec2:ModifyVolume",
          "ec2:RebootInstances",
          "ec2:RegisterInstancesWithLoadBalancer",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RunInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses",
          "ec2:CreateVpcEndpoint",
          "ec2:DeleteVpcEndpoints",
          "ec2:DescribeVpcEndpoints",
          "ec2:ModifyVpcEndpoint",
          "ec2:CreateLaunchTemplate",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeVolumes",
          "ec2:DescribeInstanceStatus",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:SetWebACL",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:AddTags",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "wafv2:ListWebACLs",
          "wafv2:ListResourcesForWebACL",
          "tag:GetResources",
          "tag:TagResources",
          "tag:UntagResources",
          "secretsmanager:GetSecretValue"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::*/*",
          "arn:aws:s3:::*",
        ]
      }
    ]
  })
}

# Attach the custom policy to the ALB Controller role
resource "aws_iam_role_policy_attachment" "alb_controller_attach" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller_policy.arn # <-- This is the key change
}