# Load balancers. Pods are registered as IP targets by the AWS Load Balancer
# Controller (TargetGroupBinding) running in each cluster - see README.

# ------------------------------------------------------------ access logs

data "aws_elb_service_account" "this" {}

resource "aws_s3_bucket" "lb_logs" {
  bucket_prefix = "${local.name}-lb-logs-"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "lb_logs" {
  bucket                  = aws_s3_bucket.lb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "lb_logs" {
  bucket = aws_s3_bucket.lb_logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ALB access logs support SSE-S3 only (not SSE-KMS).
resource "aws_s3_bucket_server_side_encryption_configuration" "lb_logs" {
  bucket = aws_s3_bucket.lb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lb_logs" {
  bucket = aws_s3_bucket.lb_logs.id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration {
      days = var.log_retention_days
    }
  }
}

data "aws_iam_policy_document" "lb_logs" {
  statement {
    sid       = "ElbLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.lb_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.lb_logs.arn, "${aws_s3_bucket.lb_logs.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "lb_logs" {
  bucket = aws_s3_bucket.lb_logs.id
  policy = data.aws_iam_policy_document.lb_logs.json
}

# ------------------------------------------------------------ internet zone

resource "aws_security_group" "internet_alb" {
  name        = "${local.name}-internet-alb"
  description = "Internet-facing ALB"
  vpc_id      = module.internet_vpc.vpc_id
  tags        = { Name = "${local.name}-internet-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "internet_alb" {
  for_each          = toset(["80", "443"])
  security_group_id = aws_security_group.internet_alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  description       = each.value == "80" ? "HTTP (redirected to HTTPS)" : "HTTPS from the internet"
}

resource "aws_vpc_security_group_egress_rule" "internet_alb_to_pods" {
  for_each          = toset(module.internet_vpc.subnet_cidrs["app"])
  security_group_id = aws_security_group.internet_alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.app_target_port
  to_port           = var.app_target_port
  description       = "To ODC runtime pods"
}

resource "aws_lb" "internet" {
  name                       = "${local.name}-inet"
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = module.internet_vpc.subnet_ids["public"]
  security_groups            = [aws_security_group.internet_alb.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = true

  access_logs {
    bucket  = aws_s3_bucket.lb_logs.id
    prefix  = "internet-alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.lb_logs]
}

resource "aws_lb_target_group" "internet_apps" {
  name        = "${local.name}-inet-apps"
  vpc_id      = module.internet_vpc.vpc_id
  target_type = "ip"
  protocol    = "HTTP"
  port        = var.app_target_port

  health_check {
    path    = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_listener" "internet_https" {
  load_balancer_arn = aws_lb.internet.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.internet_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internet_apps.arn
  }
}

resource "aws_lb_listener" "internet_http_redirect" {
  load_balancer_arn = aws_lb.internet.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}

# ------------------------------------------------------------ intranet zone

resource "aws_security_group" "intranet_alb" {
  name        = "${local.name}-intranet-alb"
  description = "Internal ALB for officers and the private API path"
  vpc_id      = module.intranet_vpc.vpc_id
  tags        = { Name = "${local.name}-intranet-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "intranet_alb_officers" {
  for_each          = toset(var.officer_cidrs)
  security_group_id = aws_security_group.intranet_alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from government network"
}

resource "aws_vpc_security_group_ingress_rule" "intranet_alb_from_nlb" {
  security_group_id            = aws_security_group.intranet_alb.id
  referenced_security_group_id = aws_security_group.api_nlb.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from the API NLB (API Gateway VPC link)"
}

resource "aws_vpc_security_group_egress_rule" "intranet_alb_to_pods" {
  for_each          = toset(module.intranet_vpc.subnet_cidrs["app"])
  security_group_id = aws_security_group.intranet_alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.app_target_port
  to_port           = var.app_target_port
  description       = "To ODC runtime pods"
}

resource "aws_lb" "intranet" {
  name                       = "${local.name}-intra"
  load_balancer_type         = "application"
  internal                   = true
  subnets                    = module.intranet_vpc.subnet_ids["alb"]
  security_groups            = [aws_security_group.intranet_alb.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = true

  access_logs {
    bucket  = aws_s3_bucket.lb_logs.id
    prefix  = "intranet-alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.lb_logs]
}

resource "aws_lb_target_group" "intranet_apps" {
  name        = "${local.name}-intra-apps"
  vpc_id      = module.intranet_vpc.vpc_id
  target_type = "ip"
  protocol    = "HTTP"
  port        = var.app_target_port

  health_check {
    path    = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_listener" "intranet_https" {
  load_balancer_arn = aws_lb.intranet.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.intranet_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.intranet_apps.arn
  }
}

# ------------------------------------------------------------ API path
# API Gateway (REST, private) -> VPC link -> internal NLB -> internal ALB -> pods.
# TLS passes through the NLB and terminates on the ALB (cert for intranet_api_hostname).

resource "aws_security_group" "api_nlb" {
  name        = "${local.name}-api-nlb"
  description = "Internal NLB behind the API Gateway VPC link"
  vpc_id      = module.intranet_vpc.vpc_id
  tags        = { Name = "${local.name}-api-nlb" }
}

resource "aws_vpc_security_group_egress_rule" "api_nlb_to_alb" {
  security_group_id            = aws_security_group.api_nlb.id
  referenced_security_group_id = aws_security_group.intranet_alb.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "To internal ALB"
}

resource "aws_lb" "api_nlb" {
  name                       = "${local.name}-api"
  load_balancer_type         = "network"
  internal                   = true
  subnets                    = module.intranet_vpc.subnet_ids["alb"]
  security_groups            = [aws_security_group.api_nlb.id]
  enable_deletion_protection = true

  # Traffic from the VPC link arrives over PrivateLink; it is already limited
  # by the API Gateway resource policy, WAF and throttling.
  enforce_security_group_inbound_rules_on_private_link_traffic = "off"
}

resource "aws_lb_target_group" "api_to_alb" {
  name        = "${local.name}-api-alb"
  vpc_id      = module.intranet_vpc.vpc_id
  target_type = "alb"
  protocol    = "TCP"
  port        = 443

  health_check {
    protocol = "HTTPS"
    path     = "/"
    matcher  = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "api_to_alb" {
  target_group_arn = aws_lb_target_group.api_to_alb.arn
  target_id        = aws_lb.intranet.arn
  port             = 443
  depends_on       = [aws_lb_listener.intranet_https]
}

resource "aws_lb_listener" "api_nlb" {
  load_balancer_arn = aws_lb.api_nlb.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_to_alb.arn
  }
}
