variable "cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
  default     = "terraform-eks-demo" # Consistent default value
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