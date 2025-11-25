#
# Provider Configuration
#

terraform {
  required_version = ">= 1.2.0"

  backend "s3" {
    bucket         = "prj-tf-state-dev2" # <--- EXACTLY MATCH THE BUCKET NAME CREATED ABOVE
    key            = "eks/terraform.tfstate"
    region         = "us-east-1" # <--- YOUR AWS REGION
    dynamodb_table = "prj-tf-locks2" # <--- EXACTLY MATCH THE DYNAMODB TABLE NAME CREATED ABOVE
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

provider "aws" {
  region = var.region
}

# Configure Helm to use the EKS cluster we create
provider "kubernetes" {
  host                   = aws_eks_cluster.demo.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.demo.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.demo.name]
    command     = "aws"
  }
}