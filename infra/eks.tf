# One private EKS cluster per zone, each running the ODC self-hosted runtime.
# Both clusters span two AZs with at least one node per AZ (active-active).

module "eks_internet" {
  source = "./modules/eks_cluster"

  name               = "${local.name}-internet"
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.internet_vpc.subnet_ids["app"]
  kms_key_arn        = aws_kms_key.main.arn
  admin_role_arns    = var.eks_admin_role_arns
  log_retention_days = var.log_retention_days

  node_instance_types = var.node_instance_types
  node_min_size       = var.internet_nodes.min
  node_desired_size   = var.internet_nodes.desired
  node_max_size       = var.internet_nodes.max

  depends_on = [aws_vpc_endpoint.interface, aws_vpc_endpoint.s3]
}

module "eks_intranet" {
  source = "./modules/eks_cluster"

  name               = "${local.name}-intranet"
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.intranet_vpc.subnet_ids["app"]
  kms_key_arn        = aws_kms_key.main.arn
  admin_role_arns    = var.eks_admin_role_arns
  log_retention_days = var.log_retention_days

  node_instance_types = var.node_instance_types
  node_min_size       = var.intranet_nodes.min
  node_desired_size   = var.intranet_nodes.desired
  node_max_size       = var.intranet_nodes.max

  depends_on = [aws_vpc_endpoint.interface, aws_vpc_endpoint.s3]
}

# Let each ALB reach the pods (IP targets) on the app port.
resource "aws_vpc_security_group_ingress_rule" "internet_pods_from_alb" {
  security_group_id            = module.eks_internet.cluster_security_group_id
  referenced_security_group_id = aws_security_group.internet_alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_target_port
  to_port                      = var.app_target_port
  description                  = "From internet-facing ALB"
}

resource "aws_vpc_security_group_ingress_rule" "intranet_pods_from_alb" {
  security_group_id            = module.eks_intranet.cluster_security_group_id
  referenced_security_group_id = aws_security_group.intranet_alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_target_port
  to_port                      = var.app_target_port
  description                  = "From internal ALB"
}
