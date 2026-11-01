# Offline plan test with a mocked AWS provider: checks the configuration
# wires together without needing AWS credentials. Run: tofu test (or terraform test)

mock_provider "aws" {
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/mock" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:ap-southeast-1:111122223333:log-group:mock" }
  }
  mock_resource "aws_wafv2_web_acl" {
    defaults = { arn = "arn:aws:wafv2:ap-southeast-1:111122223333:regional/webacl/mock/1" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-southeast-1:111122223333:loadbalancer/app/mock/1" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-southeast-1:111122223333:targetgroup/mock/1" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:ap-southeast-1:111122223333:key/mock" }
  }
  mock_resource "aws_networkfirewall_rule_group" {
    defaults = { arn = "arn:aws:network-firewall:ap-southeast-1:111122223333:stateful-rulegroup/mock" }
  }
  mock_resource "aws_api_gateway_stage" {
    defaults = { arn = "arn:aws:apigateway:ap-southeast-1::/restapis/mock/stages/v1" }
  }
  mock_resource "aws_networkfirewall_firewall_policy" {
    defaults = { arn = "arn:aws:network-firewall:ap-southeast-1:111122223333:firewall-policy/mock" }
  }
  mock_resource "aws_networkfirewall_firewall" {
    defaults = {
      arn             = "arn:aws:network-firewall:ap-southeast-1:111122223333:firewall/mock"
      firewall_status = [{ sync_states = [{ availability_zone = "ap-southeast-1a", attachment = [{ endpoint_id = "vpce-0123456789abcdef0", subnet_id = "subnet-1", status = "READY", status_message = "" }] }], capacity_usage_summary = [], transit_gateway_attachment_sync_states = [] }]
    }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mock" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::114774131450:root" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  internet_certificate_arn = "arn:aws:acm:ap-southeast-1:111122223333:certificate/a"
  intranet_certificate_arn = "arn:aws:acm:ap-southeast-1:111122223333:certificate/b"
  intranet_api_hostname    = "api.intranet.example.gov.sg"
  officer_cidrs            = ["10.0.0.0/8"]
  odc_platform_domains     = [".outsystems.com"]
  eks_admin_role_arns      = ["arn:aws:iam::111122223333:role/admin"]
}

run "plan" {
  command = plan

  assert {
    condition     = length(module.intranet_vpc.subnet_ids["app"]) == 2
    error_message = "intranet app subnets should span 2 AZs"
  }
  assert {
    condition     = length(local.interface_endpoints) == 24
    error_message = "unexpected endpoint count"
  }
}
