# Private access to AWS services, so image pulls, logs, secrets and node
# management never leave the AWS network or touch the egress allow-list.

locals {
  endpoint_vpcs = {
    internet = {
      vpc_id     = module.internet_vpc.vpc_id
      cidr       = var.internet_vpc_cidr
      subnet_ids = module.internet_vpc.subnet_ids["endpoints"]
      app_rts    = module.internet_vpc.route_table_ids["app"]
      services   = local.eks_interface_endpoints
    }
    intranet = {
      vpc_id     = module.intranet_vpc.vpc_id
      cidr       = var.intranet_vpc_cidr
      subnet_ids = module.intranet_vpc.subnet_ids["endpoints"]
      app_rts    = module.intranet_vpc.route_table_ids["app"]
      services   = concat(local.eks_interface_endpoints, ["secretsmanager", "kms"])
    }
  }

  interface_endpoints = merge([
    for zone, cfg in local.endpoint_vpcs : {
      for svc in cfg.services : "${zone}-${svc}" => {
        zone    = zone
        service = svc
      }
    }
  ]...)
}

resource "aws_security_group" "endpoints" {
  for_each    = local.endpoint_vpcs
  name        = "${local.name}-${each.key}-endpoints"
  description = "HTTPS from inside the ${each.key} VPC to AWS service endpoints"
  vpc_id      = each.value.vpc_id
  tags        = { Name = "${local.name}-${each.key}-endpoints" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  for_each          = local.endpoint_vpcs
  security_group_id = aws_security_group.endpoints[each.key].id
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from VPC"
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = local.endpoint_vpcs[each.value.zone].vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value.service}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.endpoint_vpcs[each.value.zone].subnet_ids
  security_group_ids  = [aws_security_group.endpoints[each.value.zone].id]
  private_dns_enabled = true
  tags                = { Name = "${local.name}-${each.key}" }
}

resource "aws_vpc_endpoint" "s3" {
  for_each = local.endpoint_vpcs

  vpc_id            = each.value.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = each.value.app_rts # ECR image layers are served from S3
  tags              = { Name = "${local.name}-${each.key}-s3" }
}

# The only way from the internet zone into the intranet zone: the private
# API Gateway, reached through this execute-api endpoint (PrivateLink).
resource "aws_vpc_endpoint" "execute_api" {
  vpc_id              = module.internet_vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.internet_vpc.subnet_ids["endpoints"]
  security_group_ids  = [aws_security_group.endpoints["internet"].id]
  private_dns_enabled = true
  tags                = { Name = "${local.name}-internet-execute-api" }
}
