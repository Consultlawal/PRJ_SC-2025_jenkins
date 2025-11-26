data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "demo" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name                       = "terraform-eks-demo-vpc" # Changed tag name for clarity
    "kubernetes.io/cluster/${var.cluster_name}" = "owned" # Tag for EKS cluster discovery
  }
}

resource "aws_subnet" "demo" {
  count = 3 # Create 3 subnets in 3 different AZs

  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true # These are public subnets

  vpc_id = aws_vpc.demo.id

  tags = {
    Name                       = "${var.cluster_name}-subnet-${count.index}" # Changed tag name for clarity
    "kubernetes.io/cluster/${var.cluster_name}" = "owned" # Tag for EKS cluster discovery
    "kubernetes.io/role/elb" = "1" # Tag for ALB to discover subnets
    "kubernetes.io/role/internal-elb" = "1" # Tag for internal ALB to discover subnets
  }
}

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id

  tags = {
    Name = "terraform-eks-demo-igw" # Changed tag name for clarity
  }
}

resource "aws_route_table" "demo" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }

  tags = {
    Name = "terraform-eks-demo-rt" # Changed tag name for clarity
  }
}

resource "aws_route_table_association" "demo" {
  count = 3 # Associate all 3 subnets to the route table

  subnet_id      = aws_subnet.demo[count.index].id
  route_table_id = aws_route_table.demo.id
}