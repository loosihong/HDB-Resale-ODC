# ------------------------------------------------------------------ general

variable "project" {
  description = "Short project name used in resource names."
  type        = string
  default     = "hdb-resale"
}

variable "environment" {
  description = "Environment name (prod, qa, dev)."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region. GCC 2.0 on AWS uses Singapore."
  type        = string
  default     = "ap-southeast-1"
}

variable "azs" {
  description = "Exactly two availability zones. Single-AZ resources (egress) go in the first."
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]

  validation {
    condition     = length(var.azs) == 2
    error_message = "This design uses exactly two availability zones."
  }
}

variable "extra_tags" {
  description = "Additional tags, e.g. tags required by the GCC landing zone."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Retention for CloudWatch log groups (flow logs, WAF, firewall, EKS, API Gateway)."
  type        = number
  default     = 365
}

# ------------------------------------------------------------------ network

variable "internet_vpc_cidr" {
  type    = string
  default = "10.10.0.0/20"
}

variable "intranet_vpc_cidr" {
  type    = string
  default = "10.20.0.0/20"
}

variable "data_vpc_cidr" {
  type    = string
  default = "10.30.0.0/22"
}

variable "officer_cidrs" {
  description = "Government network CIDRs allowed to reach the internal ALB. Routing from the government network is provided by GCC."
  type        = list(string)
  default     = []
}

variable "egress_allowed_domains" {
  description = "Domains the intranet zone may reach through Network Firewall (TLS SNI / HTTP Host)."
  type        = list(string)
  default     = ["data.gov.sg", ".data.gov.sg"]
}

variable "odc_platform_domains" {
  description = "OutSystems platform domains the self-hosted ODC runtime must reach (get the list from OutSystems). Allowed from both EKS zones."
  type        = list(string)
  default     = []
}

variable "enable_internet_zone_egress" {
  description = "Give the internet zone a NAT gateway (AZ a) so the ODC runtime can reach OutSystems. Restricted by Route 53 DNS Firewall."
  type        = bool
  default     = true
}

# ------------------------------------------------------------------ edge

variable "internet_certificate_arn" {
  description = "ACM certificate ARN for the public hostname on the internet-facing ALB."
  type        = string
}

variable "intranet_certificate_arn" {
  description = "ACM certificate ARN for the internal ALB. Must cover intranet_api_hostname."
  type        = string
}

variable "intranet_api_hostname" {
  description = "Hostname API Gateway uses for TLS and the Host header when it calls the intranet APIs through the VPC link. The intranet ACM certificate must cover it. It does not need to resolve: the VPC link always delivers to the NLB."
  type        = string
}

variable "app_target_port" {
  description = "Container port the ODC runtime ingress listens on (pods registered as IP targets)."
  type        = number
  default     = 8080
}

variable "waf_rate_limit_per_5min" {
  description = "Per-IP request limit over 5 minutes on the internet-facing WAF."
  type        = number
  default     = 2000
}

variable "api_throttle_rate" {
  description = "Steady-state requests per second allowed on the private API."
  type        = number
  default     = 200
}

variable "api_throttle_burst" {
  type    = number
  default = 400
}

variable "manage_apigw_cloudwatch_role" {
  description = "Set the account-level API Gateway CloudWatch Logs role. Disable if the landing zone already manages it."
  type        = bool
  default     = true
}

# ------------------------------------------------------------------ EKS

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "eks_admin_role_arns" {
  description = "Federated IAM roles (e.g. via TechPass) that get cluster-admin on both clusters. The creator gets no implicit admin, so at least one is required."
  type        = list(string)

  validation {
    condition     = length(var.eks_admin_role_arns) > 0
    error_message = "Provide at least one admin role, otherwise nobody can administer the clusters."
  }
}

variable "node_instance_types" {
  type    = list(string)
  default = ["m7i.large"]
}

variable "internet_nodes" {
  description = "Internet cluster node group size. min 2 = one node per AZ (active-active)."
  type        = object({ min = number, desired = number, max = number })
  default     = { min = 2, desired = 2, max = 6 }
}

variable "intranet_nodes" {
  description = "Intranet cluster node group size. min 2 = one node per AZ (active-active)."
  type        = object({ min = number, desired = number, max = number })
  default     = { min = 2, desired = 2, max = 6 }
}

# ------------------------------------------------------------------ database

variable "db_engine_version" {
  description = "RDS for PostgreSQL major version."
  type        = string
  default     = "17"
}

variable "db_instance_class" {
  type    = string
  default = "db.m7g.large"
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 50
}

variable "db_max_allocated_storage_gb" {
  description = "Storage autoscaling ceiling."
  type        = number
  default     = 200
}

variable "db_multi_az" {
  description = "Multi-AZ standby. Keep true in prod; set false in dev/qa to save cost."
  type        = bool
  default     = true
}

variable "db_backup_retention_days" {
  type    = number
  default = 14
}

variable "db_deletion_protection" {
  type    = bool
  default = true
}
