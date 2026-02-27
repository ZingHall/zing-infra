data "aws_availability_zones" "available" {}

locals {
  az_count = 2
  azs      = slice(data.aws_availability_zones.available.names, 0, local.az_count)
}

module "vpc_subnets" {
  source                = "../../../modules/aws/vpc-subnets"
  name                  = "zing-prod"
  vpc_cidr              = "10.0.0.0/16"
  azs                   = local.azs
  private_subnet_offset = 100
  nat_gateway_count     = 0
}
