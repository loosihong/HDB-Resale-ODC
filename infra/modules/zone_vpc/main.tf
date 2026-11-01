# One security zone = one VPC. Subnet tiers are passed in per AZ; a tier with a
# single CIDR exists only in the first AZ (used for the single-AZ egress path).

locals {
  subnet_list = flatten([
    for tier, cfg in var.subnets : [
      for idx, cidr in cfg.cidrs : {
        key    = "${tier}-${idx}"
        tier   = tier
        idx    = idx
        cidr   = cidr
        public = cfg.public
      }
    ]
  ])
  subnet_map = { for s in local.subnet_list : s.key => s }
  has_public = anytrue([for s in local.subnet_list : s.public])
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name, Zone = var.zone }
}

# Lock down the default security group so nothing can use it by accident.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-default-deny" }
}

resource "aws_internet_gateway" "this" {
  count  = local.has_public ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "this" {
  for_each = local.subnet_map

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = var.azs[each.value.idx]
  map_public_ip_on_launch = false

  tags = merge(
    { Name = "${var.name}-${each.value.tier}-${substr(var.azs[each.value.idx], -1, 1)}", Tier = each.value.tier },
    lookup(var.subnet_tags, each.value.tier, {})
  )
}

resource "aws_route_table" "this" {
  for_each = local.subnet_map
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name}-${each.value.tier}-${substr(var.azs[each.value.idx], -1, 1)}-rt" }
}

resource "aws_route_table_association" "this" {
  for_each       = local.subnet_map
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.this[each.key].id
}

resource "aws_route" "public_default" {
  for_each = { for k, s in local.subnet_map : k => s if s.public }

  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

# VPC flow logs (all traffic) to an encrypted CloudWatch log group.
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/vpc/${var.name}/flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "this" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn
}
