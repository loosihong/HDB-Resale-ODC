# Outbound internet access. Deliberately single-AZ (AZ a) to save cost: the
# only business traffic is the HDB Backend daily sync, which can retry.
#
# Intranet zone:  app subnets -> Network Firewall (domain allow-list) -> NAT -> IGW
# Internet zone:  app subnets -> NAT -> IGW, with Route 53 DNS Firewall allow-list
#
# If the GCC landing zone provides central egress, drop this file and route
# 0.0.0.0/0 to the GCC egress attachment instead.

locals {
  az_a = var.azs[0]

  nfw_endpoint_id = one([
    for s in aws_networkfirewall_firewall.egress.firewall_status[0].sync_states :
    s.attachment[0].endpoint_id if s.availability_zone == local.az_a
  ])
}

# ------------------------------------------------------------ intranet zone

resource "aws_eip" "intranet_nat" {
  domain = "vpc"
  tags   = { Name = "${local.name}-intranet-nat" }
}

resource "aws_nat_gateway" "intranet" {
  allocation_id = aws_eip.intranet_nat.id
  subnet_id     = module.intranet_vpc.subnet_ids["public"][0]
  tags          = { Name = "${local.name}-intranet-nat" }
}

resource "aws_networkfirewall_rule_group" "egress_allow" {
  name     = "${local.name}-egress-allow"
  type     = "STATEFUL"
  capacity = 100

  rule_group {
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI", "HTTP_HOST"]
        targets              = concat(var.egress_allowed_domains, var.odc_platform_domains)
      }
    }
  }
}

resource "aws_networkfirewall_firewall_policy" "egress" {
  name = "${local.name}-egress"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    # Anything not explicitly allowed (any protocol, any domain) is dropped.
    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }
    stateful_default_actions = ["aws:drop_established", "aws:alert_established"]

    stateful_rule_group_reference {
      priority     = 100
      resource_arn = aws_networkfirewall_rule_group.egress_allow.arn
    }
  }
}

resource "aws_networkfirewall_firewall" "egress" {
  name                = "${local.name}-egress"
  vpc_id              = module.intranet_vpc.vpc_id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.egress.arn
  delete_protection   = true

  subnet_mapping {
    subnet_id = module.intranet_vpc.subnet_ids["firewall"][0]
  }

  encryption_configuration {
    type   = "CUSTOMER_KMS"
    key_id = aws_kms_key.main.arn
  }
}

resource "aws_cloudwatch_log_group" "nfw" {
  for_each          = toset(["alert", "flow"])
  name              = "/network-firewall/${local.name}-egress/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn
}

resource "aws_networkfirewall_logging_configuration" "egress" {
  firewall_arn = aws_networkfirewall_firewall.egress.arn

  logging_configuration {
    log_destination_config {
      log_type             = "ALERT"
      log_destination_type = "CloudWatchLogs"
      log_destination      = { logGroup = aws_cloudwatch_log_group.nfw["alert"].name }
    }
    log_destination_config {
      log_type             = "FLOW"
      log_destination_type = "CloudWatchLogs"
      log_destination      = { logGroup = aws_cloudwatch_log_group.nfw["flow"].name }
    }
  }
}

# App subnets (both AZs) send internet-bound traffic to the firewall in AZ a.
resource "aws_route" "intranet_app_default" {
  count                  = length(var.azs)
  route_table_id         = module.intranet_vpc.route_table_ids["app"][count.index]
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.nfw_endpoint_id
}

# Firewall subnet -> NAT
resource "aws_route" "intranet_firewall_default" {
  route_table_id         = module.intranet_vpc.route_table_ids["firewall"][0]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.intranet.id
}

# Return path: NAT subnet sends replies for the app subnets back through the firewall.
resource "aws_route" "intranet_public_return" {
  count                  = length(var.azs)
  route_table_id         = module.intranet_vpc.route_table_ids["public"][0]
  destination_cidr_block = module.intranet_vpc.subnet_cidrs["app"][count.index]
  vpc_endpoint_id        = local.nfw_endpoint_id
}

# ------------------------------------------------------------ internet zone

resource "aws_eip" "internet_nat" {
  count  = var.enable_internet_zone_egress ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${local.name}-internet-nat" }
}

resource "aws_nat_gateway" "internet" {
  count         = var.enable_internet_zone_egress ? 1 : 0
  allocation_id = aws_eip.internet_nat[0].id
  subnet_id     = module.internet_vpc.subnet_ids["public"][0]
  tags          = { Name = "${local.name}-internet-nat" }
}

resource "aws_route" "internet_app_default" {
  count                  = var.enable_internet_zone_egress ? length(var.azs) : 0
  route_table_id         = module.internet_vpc.route_table_ids["app"][count.index]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.internet[0].id
}

# DNS Firewall: the internet zone may only resolve AWS service names, internal
# names and the OutSystems platform. Everything else gets no answer.
resource "aws_route53_resolver_firewall_domain_list" "internet_allow" {
  name = "${local.name}-internet-allow"
  domains = concat(
    ["amazonaws.com", "*.amazonaws.com", "*.internal"],
    [for d in var.odc_platform_domains : "*.${trimprefix(d, ".")}"],
    [for d in var.odc_platform_domains : trimprefix(d, ".")],
  )
}

resource "aws_route53_resolver_firewall_domain_list" "internet_block_all" {
  name    = "${local.name}-internet-block-all"
  domains = ["*"]
}

resource "aws_route53_resolver_firewall_rule_group" "internet" {
  name = "${local.name}-internet-dns"
}

resource "aws_route53_resolver_firewall_rule" "internet_allow" {
  name                    = "allow-listed"
  action                  = "ALLOW"
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.internet_allow.id
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.internet.id
  priority                = 100
}

resource "aws_route53_resolver_firewall_rule" "internet_block" {
  name                    = "block-everything-else"
  action                  = "BLOCK"
  block_response          = "NODATA"
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.internet_block_all.id
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.internet.id
  priority                = 200
}

resource "aws_route53_resolver_firewall_rule_group_association" "internet" {
  name                   = "${local.name}-internet-dns"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.internet.id
  vpc_id                 = module.internet_vpc.vpc_id
  priority               = 101
}
