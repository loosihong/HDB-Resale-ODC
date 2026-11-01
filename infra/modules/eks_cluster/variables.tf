variable "name" {
  description = "Cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
}

variable "subnet_ids" {
  description = "Private app subnets, one per AZ."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key for secrets encryption, node volumes and logs."
  type        = string
}

variable "admin_role_arns" {
  description = "IAM role ARNs granted cluster-admin through EKS access entries."
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  type = list(string)
}

variable "node_ami_type" {
  type    = string
  default = "AL2023_x86_64_STANDARD"
}

variable "node_min_size" {
  type = number
}

variable "node_desired_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "node_disk_size_gb" {
  type    = number
  default = 50
}

variable "log_retention_days" {
  type = number
}
