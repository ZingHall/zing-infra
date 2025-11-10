locals {
  public_subnet_cidrs  = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 8, i + var.private_subnet_offset)]
  nat_gateway_indices  = [for i in range(var.nat_gateway_count) : floor(i * length(var.azs) / var.nat_gateway_count)]
}

resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_cidr
  instance_tenancy                 = "default"
  assign_generated_ipv6_cidr_block = false
  enable_dns_support               = true
  enable_dns_hostnames             = true
  tags = {
    name = "${var.name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    name = "${var.name}-igw"
  }
}

### Public Subnets

resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = var.azs[count.index]
  tags = {
    name = "${var.name}-public-${count.index + 1}"
    type = "public"
  }
}

resource "aws_route_table" "public" {
  count  = length(var.azs)
  vpc_id = aws_vpc.main.id
  tags = {
    name = "${var.name}-public-rt-${count.index + 1}"
  }
}

resource "aws_route" "public_igw" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.public[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[count.index].id
}

### Private Subnets

resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = {
    name = "${var.name}-private-${count.index + 1}"
    type = "private"
  }
}

resource "aws_route_table" "private" {
  count  = length(var.azs)
  vpc_id = aws_vpc.main.id
  tags = {
    name = "${var.name}-private-rt-${count.index + 1}"
  }
}
resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

### NAT Gateway

resource "aws_eip" "nat" {
  count = var.nat_gateway_count

  tags = {
    name                = "${var.name}-nat-eip-${count.index + 1}"
    used_by_nat_gateway = "${var.name}-nat-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "nat" {
  count         = var.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[local.nat_gateway_indices[count.index]].id
  tags = {
    name = "${var.name}-nat-${count.index + 1}"
  }
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route" "private_nat" {
  count                  = var.nat_gateway_count > 0 ? length(var.azs) : 0
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[count.index % var.nat_gateway_count].id
}
