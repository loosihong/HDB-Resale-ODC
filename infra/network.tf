# Three security zones, each in its own VPC (see the deployment diagram).

module "internet_vpc" {
  source = "./modules/zone_vpc"

  name               = "${local.name}-internet"
  zone               = "internet"
  cidr               = var.internet_vpc_cidr
  azs                = var.azs
  subnets            = local.internet_subnets
  kms_key_arn        = aws_kms_key.main.arn
  log_retention_days = var.log_retention_days
}

module "intranet_vpc" {
  source = "./modules/zone_vpc"

  name               = "${local.name}-intranet"
  zone               = "intranet"
  cidr               = var.intranet_vpc_cidr
  azs                = var.azs
  subnets            = local.intranet_subnets
  kms_key_arn        = aws_kms_key.main.arn
  log_retention_days = var.log_retention_days
}

module "data_vpc" {
  source = "./modules/zone_vpc"

  name               = "${local.name}-data"
  zone               = "data"
  cidr               = var.data_vpc_cidr
  azs                = var.azs
  subnets            = local.data_subnets
  kms_key_arn        = aws_kms_key.main.arn
  log_retention_days = var.log_retention_days
}

# ------------------------------------------------------------ Transit Gateway
# Only the intranet and data zones are attached. The internet zone has no
# network path to the other zones at all: it reaches intranet APIs only through
# the private API Gateway (PrivateLink), which is the single controlled entry.

resource "aws_ec2_transit_gateway" "this" {
  description                     = "${local.name} zone routing"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments  = "disable"
  dns_support                     = "enable"
  tags                            = { Name = "${local.name}-tgw" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "intranet" {
  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  vpc_id                                          = module.intranet_vpc.vpc_id
  subnet_ids                                      = module.intranet_vpc.subnet_ids["tgw"]
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags                                            = { Name = "${local.name}-tgw-intranet" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "data" {
  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  vpc_id                                          = module.data_vpc.vpc_id
  subnet_ids                                      = module.data_vpc.subnet_ids["tgw"]
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags                                            = { Name = "${local.name}-tgw-data" }
}

resource "aws_ec2_transit_gateway_route_table" "zones" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "${local.name}-tgw-zones" }
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each = {
    intranet = aws_ec2_transit_gateway_vpc_attachment.intranet.id
    data     = aws_ec2_transit_gateway_vpc_attachment.data.id
  }
  transit_gateway_attachment_id  = each.value
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.zones.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  for_each = {
    intranet = aws_ec2_transit_gateway_vpc_attachment.intranet.id
    data     = aws_ec2_transit_gateway_vpc_attachment.data.id
  }
  transit_gateway_attachment_id  = each.value
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.zones.id
}

# Intranet app subnets -> data zone
resource "aws_route" "intranet_app_to_data" {
  count                  = length(var.azs)
  route_table_id         = module.intranet_vpc.route_table_ids["app"][count.index]
  destination_cidr_block = var.data_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.intranet]
}

# Data db subnets -> intranet zone (return path)
resource "aws_route" "data_db_to_intranet" {
  count                  = length(var.azs)
  route_table_id         = module.data_vpc.route_table_ids["db"][count.index]
  destination_cidr_block = var.intranet_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.data]
}
