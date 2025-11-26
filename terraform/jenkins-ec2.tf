###############################
# JENKINS IAM ROLE + PROFILE #
###############################
resource "aws_iam_role" "jenkins_role" {
  name = "jenkins-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "jenkins_role_policy" {
  name = "jenkins-policy"
  role = aws_iam_role.jenkins_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "eks:DescribeCluster",
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeRepositories",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "s3:GetObject",  # Added for S3 backend access
          "s3:PutObject",  # Added for S3 backend access
          "s3:ListBucket", # Added for S3 backend access
          "s3:DeleteObject", # Added for S3 backend access
          "dynamodb:GetItem", # Added for DynamoDB lock table
          "dynamodb:PutItem", # Added for DynamoDB lock table
          "dynamodb:DeleteItem", # Added for DynamoDB lock table
          "dynamodb:UpdateItem" # Added for DynamoDB lock table
        ]
        Resource = "*"
      },
      { # Permissions for EKS cluster operations
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:ListClusters",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "iam:ListRoles",
          "iam:ListUsers",
          "iam:GetUser", # Needed for general IAM operations, even if not creating users
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = "*"
      },
      { # Permissions for creating EKS related resources by Terraform
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:PutRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DeleteRole",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy",
          "ec2:CreateSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup",
          "ec2:CreateSubnet",
          "ec2:DeleteSubnet",
          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:CreateInternetGateway",
          "ec2:DeleteInternetGateway",
          "ec2:CreateRouteTable",
          "ec2:DeleteRouteTable",
          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "eks:CreateCluster",
          "eks:DeleteCluster",
          "eks:CreateNodegroup",
          "eks:DeleteNodegroup",
          "eks:UpdateNodegroupConfig",
          "eks:UpdateClusterVersion",
          "eks:UpdateNodegroupVersion",
          "eks:UpdateClusterConfig",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeListeners",
          "route53:CreateHostedZone",
          "route53:DeleteHostedZone",
          "route53:ChangeResourceRecordSets",
          "route53:ListHostedZones",
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "s3:CreateBucket",
          "s3:PutBucketVersioning",
          "s3:PutLifecycleConfiguration",
          "s3:DeleteBucket"
        ]
        Resource = "*"
      },
      { # Permissions for TLS certificate data source
        Effect   = "Allow"
        Action   = [
          "acm:DescribeCertificate",
          "acm:GetCertificate"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins_instance_profile" {
  name = "jenkins-ec2-profile"
  role = aws_iam_role.jenkins_role.name
}

###############################
# JENKINS SECURITY GROUP      #
###############################
resource "aws_security_group" "jenkins_sg" {
  name        = "${var.cluster_name}-jenkins-sg"
  vpc_id      = aws_vpc.demo.id

  ingress {
    description = "Jenkins UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # WARNING: This allows access from anywhere. Restrict for production.
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # WARNING: This allows access from anywhere. Restrict for production.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins-sg"
  }
}

############################################################
# 1. TLS KEYPAIR FOR JENKINS EC2 (same structure as worker nodes)
############################################################

resource "tls_private_key" "jenkins_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "jenkins_private_key" {
  content         = tls_private_key.jenkins_key.private_key_pem
  filename        = "${var.cluster_name}-jenkins-key.pem"
  file_permission = 400
}

resource "aws_key_pair" "jenkins_public_key" {
  key_name   = "${var.cluster_name}-jenkins-public-key"
  public_key = tls_private_key.jenkins_key.public_key_openssh
}

###############################
# JENKINS EC2 INSTANCE        #
###############################
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"] # Official Amazon AMIs

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"] # Matches Amazon Linux 2 HVM AMIs
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


resource "aws_instance" "jenkins" {
  # CORRECTED: Replaced invalid AMI ID with a known Amazon Linux 2 AMI for us-east-1
  # Always verify the latest AMI for your region and desired OS:
  # https://aws.amazon.com/amazon-linux-2/
  ami           = data.aws_ami.amazon_linux_2.id # Amazon Linux 2 (HVM), SSD Volume Type for us-east-1 (as of late 2023/early 2024)
  instance_type = "t3.medium"
  key_name      = aws_key_pair.jenkins_public_key.key_name
  subnet_id     = aws_subnet.demo[0].id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]

  iam_instance_profile = aws_iam_instance_profile.jenkins_instance_profile.name # UNCOMMENTED: Ensure instance profile is attached

    user_data = <<-EOF
#!/bin/bash
set -ex

yum update -y

# Install Java 11
# amazon-linux-extras install java-openjdk11 -y
yum install java-11-amazon-corretto -y

# Add Jenkins repo
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo

# Import updated Jenkins GPG key
curl -fsSL https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key -o /tmp/jenkins.key
rpm --import /tmp/jenkins.key
rm -f /tmp/jenkins.key

# Install Jenkins
yum install jenkins -y


# Enable/start Jenkins
systemctl enable jenkins
systemctl start jenkins

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install --update
rm -rf awscliv2.zip aws/

# Install Docker
yum install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker jenkins

# Install Terraform
yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
yum install -y terraform

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh


# Permissions fix: ensure jenkins can access docker socket
chmod 666 /var/run/docker.sock || true

# DO NOT REBOOT in user-data — causes cloud-init failure
EOF


  tags = {
    Name = "Jenkins-Server"
  }
}

###############################
# OUTPUTS                     #
###############################
output "jenkins_public_ip" {
  description = "Public IP of Jenkins EC2"
  value       = aws_instance.jenkins.public_ip
}

output "jenkins_url" {
  description = "URL for Jenkins Web UI"
  value       = "http://${aws_instance.jenkins.public_ip}:8080"
}