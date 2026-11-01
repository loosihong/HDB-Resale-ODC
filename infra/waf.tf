# AWS WAF for both zones (defence in depth: intranet users are not trusted by default).
#   internet  -> internet-facing ALB        (managed rules + IP reputation + rate limit)
#   intranet  -> internal ALB and private API Gateway stage

locals {
  waf_acls = {
    internet = {
      managed_rules = [
        "AWSManagedRulesAmazonIpReputationList",
        "AWSManagedRulesCommonRuleSet",
        "AWSManagedRulesKnownBadInputsRuleSet",
        "AWSManagedRulesSQLiRuleSet",
      ]
      rate_limit = var.waf_rate_limit_per_5min
    }
    intranet = {
      managed_rules = [
        "AWSManagedRulesCommonRuleSet",
        "AWSManagedRulesKnownBadInputsRuleSet",
        "AWSManagedRulesSQLiRuleSet",
      ]
      rate_limit = null
    }
  }
}

resource "aws_wafv2_web_acl" "this" {
  for_each = local.waf_acls

  name  = "${local.name}-${each.key}"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = each.value.rate_limit == null ? [] : [each.value.rate_limit]
    content {
      name     = "rate-limit-per-ip"
      priority = 0

      action {
        block {}
      }

      statement {
        rate_based_statement {
          limit              = rule.value
          aggregate_key_type = "IP"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${each.key}-rate-limit"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = each.value.managed_rules
    content {
      name     = rule.value
      priority = rule.key + 1

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.value
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${each.key}-${rule.value}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-${each.key}"
    sampled_requests_enabled   = true
  }
}

# WAF log group names must start with "aws-waf-logs-".
resource "aws_cloudwatch_log_group" "waf" {
  for_each          = local.waf_acls
  name              = "aws-waf-logs-${local.name}-${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  for_each                = local.waf_acls
  resource_arn            = aws_wafv2_web_acl.this[each.key].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[each.key].arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
}

resource "aws_wafv2_web_acl_association" "internet_alb" {
  resource_arn = aws_lb.internet.arn
  web_acl_arn  = aws_wafv2_web_acl.this["internet"].arn
}

resource "aws_wafv2_web_acl_association" "intranet_alb" {
  resource_arn = aws_lb.intranet.arn
  web_acl_arn  = aws_wafv2_web_acl.this["intranet"].arn
}

resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_api_gateway_stage.v1.arn
  web_acl_arn  = aws_wafv2_web_acl.this["intranet"].arn
}
