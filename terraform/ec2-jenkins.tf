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
          "logs:PutLogEvents"
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
  name        = "jenkins-sg"
  description = "Allow Jenkins UI + SSH"
  vpc_id      = var.vpc_id

  ingress {
    description = "Jenkins UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

###############################
# JENKINS EC2 INSTANCE        #
###############################
resource "aws_instance" "jenkins" {
  ami           = var.jenkins_ami_id
  instance_type = "t3.medium"
  key_name      = var.keypair
  subnet_id     = var.public_subnet_id
  security_groups = [
    aws_security_group.jenkins_sg.id
  ]

  iam_instance_profile = aws_iam_instance_profile.jenkins_instance_profile.name

  user_data = <<-EOF
#!/bin/bash
set -e

# Update
yum update -y

# Install Java
amazon-linux-extras install java-openjdk11 -y

# Add Jenkins repo
wget -O /etc/yum.repos.d/jenkins.repo \
  https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key

# Install Jenkins
yum install jenkins -y

# Start Jenkins
systemctl enable jenkins
systemctl start jenkins

# Install Docker
yum install docker -y
systemctl enable docker
systemctl start docker
usermod -aG docker jenkins

# Reboot to apply Docker group rights
reboot
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
