variable "name" {
  description = "Name prefix for the VPC and its resources."
  type        = string
}

variable "zone" {
  description = "Security zone this VPC represents (internet, intranet or data)."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block."
  type        = string
}

variable "azs" {
  description = "Availability zones, in order. Subnet CIDR index i is placed in azs[i]."
  type        = list(string)
}

variable "subnets" {
  description = "Subnet tiers. Each tier lists one CIDR per AZ (or one CIDR for an AZ-a-only tier)."
  type = map(object({
    cidrs  = list(string)
    public = optional(bool, false)
  }))
}

variable "subnet_tags" {
  description = "Extra tags per tier, e.g. Kubernetes load balancer discovery tags."
  type        = map(map(string))
  default     = {}
}

variable "kms_key_arn" {
  description = "KMS key used to encrypt the flow log group."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for VPC flow logs."
  type        = number
}
