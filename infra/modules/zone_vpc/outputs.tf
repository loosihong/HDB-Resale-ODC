output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "subnet_ids" {
  description = "Map of tier => list of subnet IDs in AZ order."
  value = {
    for tier, cfg in var.subnets : tier => [for idx in range(length(cfg.cidrs)) : aws_subnet.this["${tier}-${idx}"].id]
  }
}

output "subnet_cidrs" {
  description = "Map of tier => list of subnet CIDRs in AZ order."
  value       = { for tier, cfg in var.subnets : tier => cfg.cidrs }
}

output "route_table_ids" {
  description = "Map of tier => list of route table IDs in AZ order."
  value = {
    for tier, cfg in var.subnets : tier => [for idx in range(length(cfg.cidrs)) : aws_route_table.this["${tier}-${idx}"].id]
  }
}

output "internet_gateway_id" {
  value = try(aws_internet_gateway.this[0].id, null)
}
