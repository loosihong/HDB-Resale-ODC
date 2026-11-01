output "internet_alb_dns_name" {
  description = "Point the public hostname (CNAME/alias) here."
  value       = aws_lb.internet.dns_name
}

output "intranet_alb_dns_name" {
  description = "Point the intranet hostname here (resolvable from the government network)."
  value       = aws_lb.intranet.dns_name
}

output "internet_target_group_arn" {
  description = "Use in a TargetGroupBinding in the internet cluster."
  value       = aws_lb_target_group.internet_apps.arn
}

output "intranet_target_group_arn" {
  description = "Use in a TargetGroupBinding in the intranet cluster."
  value       = aws_lb_target_group.intranet_apps.arn
}

output "private_api_invoke_url" {
  description = "Private API base URL, callable only from the internet zone VPC."
  value       = aws_api_gateway_stage.v1.invoke_url
}

output "eks_clusters" {
  value = {
    internet = module.eks_internet.cluster_name
    intranet = module.eks_intranet.cluster_name
  }
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_master_secret_arn" {
  description = "Secrets Manager secret holding the RDS master credentials."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}

output "egress_nat_public_ip" {
  description = "Source IP for outbound calls from the intranet zone (give to partners if they allow-list)."
  value       = aws_eip.intranet_nat.public_ip
}

output "kms_key_arn" {
  value = aws_kms_key.main.arn
}
