# HDB Resale on ODC: GCC 2.0 (AWS) infrastructure

Terraform for the **Deployment Architecture (Physical, Multi-AZ)** diagram: three security
zones in their own VPCs, two availability zones, the ODC self-hosted runtime on EKS, and
AWS-native edge, egress and data services.

```
Public users ──► AWS WAF ─► internet ALB ─► EKS (internet)  ── REST ──► private API Gateway
                                            BEUP, HDB Portal              │ (execute-api endpoint)
                                                                          ▼ VPC link
Officers ──────► AWS WAF ─► internal ALB ◄──────────────── internal NLB ◄─┘
                                 │
                                 ▼
                           EKS (intranet) ── TGW ──► RDS PostgreSQL Multi-AZ (data zone)
                           BAP, BAM, UM, HDB Backend
                                 │
                                 ▼  Network Firewall (domain allow-list) ► NAT ► data.gov.sg
```

## What it builds

| File | Resources | Diagram element |
|---|---|---|
| `network.tf`, `modules/zone_vpc` | 3 VPCs, subnets per tier per AZ, flow logs, Transit Gateway (intranet ↔ data only) | Zone VPCs, AZ a / AZ b, Transit Gateway |
| `egress.tf` | Network Firewall + NAT in AZ a for the intranet zone; NAT + Route 53 DNS Firewall for the internet zone | Network Firewall + NAT (AZ a only) |
| `endpoints.tf` | Interface endpoints (ECR, STS, logs, SSM, Secrets Manager, KMS...), S3 gateway, `execute-api` | Private AWS access; the only internet → intranet path |
| `waf.tf` | Web ACLs for both zones, logging, associations (ALBs + API stage) | AWS WAF (both zones) |
| `alb.tf` | Internet ALB, internal ALB, API NLB, target groups, access-log bucket | ALBs |
| `apigw.tf` | Private REST API, VPC link, resource policy, stage with logs and throttling | Amazon API Gateway (private) |
| `eks.tf`, `modules/eks_cluster` | Two private EKS clusters, a node group across both AZs, add-ons, access entries | EKS clusters, worker nodes per AZ |
| `rds.tf` | RDS for PostgreSQL Multi-AZ, parameter group (TLS forced), subnet group, SG | RDS primary / standby |
| `kms.tf` | Customer-managed key with rotation | Encryption at rest everywhere |

About 240 resources in total.

## Design decisions

- **The internet zone is not attached to the Transit Gateway.** Its only route into the intranet
  zone is the private API Gateway (PrivateLink), whose resource policy only accepts the
  internet VPC's `execute-api` endpoint.
- **Active-active compute, active-passive database.** Each node group spans both AZs with
  `min = 2`. RDS keeps a synchronous standby with automatic failover.
- **Egress is single-AZ on purpose.** It only carries the daily data.gov.sg sync, which can retry.
  This saves a second firewall endpoint and NAT gateway.
- **Everything is private by default.** The EKS API endpoint is private only, nodes use IMDSv2 with
  hop limit 1 (pods can't borrow node credentials), there's no SSH (Session Manager instead),
  RDS isn't public and forces TLS, and the default security groups are emptied.
- **Logs:** VPC flow logs, WAF, Network Firewall, EKS control plane, API Gateway access and
  ALB access logs, all KMS-encrypted except ALB logs (S3 SSE-S3 is the only option there).

> Note: the internet zone also gets a NAT gateway (AZ a) so the ODC runtime can reach the
> OutSystems platform. It's locked down by DNS Firewall to AWS names and `odc_platform_domains`.
> Set `enable_internet_zone_egress = false` if your ODC setup doesn't need it. This component
> isn't drawn on the diagram.

## Prerequisites

1. GCC 2.0 AWS account(s) and a deployment role with permission for the services above.
2. ACM certificates in `ap-southeast-1`:
   - public hostname for the internet ALB
   - intranet hostname for the internal ALB; it must also cover `intranet_api_hostname`
3. The list of OutSystems platform domains for the self-hosted ODC runtime (`odc_platform_domains`).
4. A federated admin role (for example, mapped through TechPass) for `eks_admin_role_arns`.
5. Terraform ≥ 1.6 or OpenTofu ≥ 1.6, AWS provider 6.x.

## Deploy

```bash
cp backend.tf.example backend.tf          # set your state bucket
cp terraform.tfvars.example terraform.tfvars   # fill in ARNs, CIDRs, domains

terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Offline check (no AWS credentials needed, uses a mocked provider):

```bash
terraform init -backend=false && terraform test
```

## After apply

1. **AWS Load Balancer Controller:** install it in both clusters (Helm) with an EKS Pod Identity
   role using AWS's published IAM policy. Then bind the ODC runtime ingress service to the
   target groups with a `TargetGroupBinding` (outputs `internet_target_group_arn`,
   `intranet_target_group_arn`).
2. **Autoscaling:** install Karpenter or Cluster Autoscaler so the node groups scale beyond
   the 2-node baseline.
3. **ODC self-hosted runtime:** install it into both clusters following OutSystems' instructions,
   then publish apps from ODC Studio. The `InitializeData` and `BootstrapAccessControl`
   timers in Basic Access Management seed the initial data and access control.
4. **DNS:** point the public hostname at `internet_alb_dns_name`, and the intranet hostname at
   `intranet_alb_dns_name` in the government network's DNS.
5. **Internet-zone apps** call intranet APIs at `private_api_invoke_url`.

## GCC-specific notes

- **Guardrails:** the GCC landing zone may block or pre-provision some resources (internet
  gateways, NAT, VPCs). If GCC provides central egress, remove `egress.tf` and route
  `0.0.0.0/0` to the GCC egress attachment. Ask GovTech to allow-list `data.gov.sg` and the ODC
  platform domains.
- **Officer access:** routing from the government network to the internal ALB is provided by
  GCC. This code only opens the internal ALB to `officer_cidrs`.
- **Central security services:** GuardDuty, Security Hub, CloudTrail and AWS Config are
  usually enabled centrally by the landing zone, so they aren't created here.
- **API Gateway logging role:** `manage_apigw_cloudwatch_role` sets an account-wide value.
  Turn it off if the landing zone already sets it.

## Cost levers (dev / qa)

```hcl
db_multi_az            = false
db_deletion_protection = false
internet_nodes         = { min = 1, desired = 1, max = 3 }
intranet_nodes         = { min = 1, desired = 1, max = 3 }
```

The biggest fixed costs are the Network Firewall endpoint, the NAT gateways, the interface
endpoints (24 × 2 AZs) and the RDS standby. Trim `local.eks_interface_endpoints` if you don't
use a service.

## Assumptions to confirm

- OutSystems supports the ODC self-hosted runtime on Amazon EKS in your setup, and the
  container port matches `app_target_port`.
- The data classification of the HDB data and the user data fits GCC 2.0. Confidential data
  would point to GCC+ / Dedicated Local Zones.
