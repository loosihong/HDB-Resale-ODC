locals {
  name = "${var.project}-${var.environment}"

  tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.extra_tags)

  # Subnet plan (two AZs). Tiers with a single CIDR exist only in AZ a.
  internet_subnets = {
    public    = { cidrs = [cidrsubnet(var.internet_vpc_cidr, 4, 0), cidrsubnet(var.internet_vpc_cidr, 4, 1)], public = true } # internet ALB, NAT
    endpoints = { cidrs = [cidrsubnet(var.internet_vpc_cidr, 4, 2), cidrsubnet(var.internet_vpc_cidr, 4, 3)] }                # VPC interface endpoints
    app       = { cidrs = [cidrsubnet(var.internet_vpc_cidr, 2, 1), cidrsubnet(var.internet_vpc_cidr, 2, 2)] }                # EKS nodes and pods
  }

  intranet_subnets = {
    public    = { cidrs = [cidrsubnet(var.intranet_vpc_cidr, 6, 0)], public = true }                             # NAT gateway, AZ a only
    firewall  = { cidrs = [cidrsubnet(var.intranet_vpc_cidr, 6, 2)] }                                            # Network Firewall endpoint, AZ a only
    tgw       = { cidrs = [cidrsubnet(var.intranet_vpc_cidr, 8, 16), cidrsubnet(var.intranet_vpc_cidr, 8, 17)] } # Transit Gateway attachment
    alb       = { cidrs = [cidrsubnet(var.intranet_vpc_cidr, 4, 2), cidrsubnet(var.intranet_vpc_cidr, 4, 3)] }   # internal ALB + NLB
    endpoints = { cidrs = [cidrsubnet(var.intranet_vpc_cidr, 4, 4), cidrsubnet(var.intranet_vpc_cidr, 4, 5)] }   # VPC interface endpoints
    app       = { cidrs = [cidrsubnet(var.intranet_vpc_cidr, 2, 2), cidrsubnet(var.intranet_vpc_cidr, 2, 3)] }   # EKS nodes and pods
  }

  data_subnets = {
    db  = { cidrs = [cidrsubnet(var.data_vpc_cidr, 2, 0), cidrsubnet(var.data_vpc_cidr, 2, 1)] }
    tgw = { cidrs = [cidrsubnet(var.data_vpc_cidr, 6, 32), cidrsubnet(var.data_vpc_cidr, 6, 33)] }
  }

  # AWS services the private EKS nodes reach through interface endpoints.
  eks_interface_endpoints = [
    "ec2", "ecr.api", "ecr.dkr", "sts", "logs", "eks-auth",
    "elasticloadbalancing", "autoscaling",
    "ssm", "ssmmessages", "ec2messages",
  ]
}
