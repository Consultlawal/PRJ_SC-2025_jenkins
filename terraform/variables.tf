#
# Variables Configuration
#

variable "cluster-name" {
  default = "terraform-eks-demo"
  type    = string
}
variable "key_pair_name" {
  default = "ekskey"
}
variable "eks_node_instance_type" {
  default = "t3.medium"
}
variable "region" {
  default = "us-east-1"
}
variable "cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
  default     = "terraform-eks-demo" # Matches the CLUSTER_NAME in your YAML
}
variable "vpc_id" {}
variable "public_subnet_id" {}
variable "keypair" {}
variable "jenkins_ami_id" {
  description = "Amazon Linux 2 AMI"
}
