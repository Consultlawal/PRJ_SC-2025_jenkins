#
# VPC Resources
#  * VPC
#  * Subnets
#  * Internet Gateway
#  * Route Table
#
// In terraform/vpc.tf (add this data block)

data "aws_availability_zones" "available" {
  # This fetches all available AZs in the current region
  state = "available"
}

// The rest of your vpc.tf file uses this data source

resource "aws_vpc" "demo" {
  cidr_block = "10.0.0.0/16"

  tags = {
  Name                           = "terraform-eks-demo-node"
  "eks.amazonaws.com/cluster-name" = var.cluster-name
  "eks.amazonaws.com/nodegroup"    = "demo"
}

}

resource "aws_subnet" "demo" {
  count = 3 # Create 3 subnets in 3 different AZs

  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.demo.id

  tags = {
  Name                           = "terraform-eks-demo-node"
  "eks.amazonaws.com/cluster-name" = var.cluster-name
  "eks.amazonaws.com/nodegroup"    = "demo"
}

}

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id

  tags = {
    Name = "terraform-eks-demo"
  }
}

resource "aws_route_table" "demo" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }
}

resource "aws_route_table_association" "demo" {
  count = 2

  subnet_id      = aws_subnet.demo[count.index].id
  route_table_id = aws_route_table.demo.id
}
