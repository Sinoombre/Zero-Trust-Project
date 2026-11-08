# Zero Trust en AWS — Proyecto 08

![Terraform >= 1.5.0](https://img.shields.io/badge/Terraform-%3E%3D1.5.0-7B42BC?logo=terraform)
[![AWS](https://custom-icon-badges.demolab.com/badge/AWS-%23FF9900.svg?logo=aws&logoColor=white)](#)

Infraestructura como código (Terraform) con arquitectura Zero Trust y cumplimiento de AWS Foundational Security Best Practices, para AWS Academy. El flujo principal es que un operador configura variables y aplica el stack Terraform, que provisiona una red y una aplicación protegida junto con controles de seguridad, registro y detección.

## Estructura

```text
.
├── .github/
│   └── workflows/
│       ├── checkov.yml               # escaneo de seguridad Checkov en cada PR/push sobre terraform/
│       └── terraform.yml             # fmt, validate y tflint en cada PR
├── docs/                             # runbook, threat model (evidencias/ no se versiona)
└── terraform/
    ├── versions.tf                   # versiones de Terraform y providers
    ├── providers.tf                  # provider AWS y default_tags
    ├── variables.tf
    ├── outputs.tf
    ├── main.tf                       # datos compartidos y sufijo aleatorio
    ├── network.tf                    # VPC, subredes, NAT opcional, VPC endpoints
    ├── security_groups.tf            # SGs (0.0.0.0/0 solo en el ALB)
    ├── compute.tf                    # EC2 privada (IMDSv2, sin IP pública, monitoring detallado, EBS-optimized)
    ├── load_balancer.tf              # ALB con ACM, redirect HTTP→HTTPS, HTTPS listener TLS 1.2
    ├── waf.tf                        # WAFv2: OWASP, Known Bad Inputs, IP Reputation, rate limit, logging
    ├── roles.tf                      # todos los roles IAM
    ├── s3.tf                         # todos los buckets (logs, config, trail) + versioning, KMS, replicación, notificaciones
    ├── logging.tf                    # VPC Flow Logs + cifrado KMS en CloudWatch Log Groups
    ├── config.tf                     # AWS Config y reglas managed (graba todos los recursos)
    ├── cloudtrail.tf                 # CloudTrail multi-región, cifrado KMS, SNS, CloudWatch Logs
    ├── detection.tf                  # GuardDuty, Security Hub, Access Analyzer
    ├── account_hardening.tf          # controles a nivel de cuenta
    ├── budgets.tf                    # alertas de costo
    └── terraform.tfvars.example
```

## Uso

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # editar alert_email y budget_limit_usd
terraform init
terraform plan
terraform apply
```

## Destruir el laboratorio

El ALB tiene protección contra borrado. Antes de `terraform destroy`:

```bash
terraform apply -var="alb_deletion_protection=false"
terraform destroy
```

## Costos

NAT Gateway, endpoints de interfaz y los servicios de seguridad generan cargos.
Revise `enable_nat_gateway`, `enable_ssm_interface_endpoints`,
`enable_ec2_interface_endpoint` y `enable_security_services` antes de aplicar.

## Equipo

**Firmes por Palmer:**

- Mario Alberto Julio Wilches.
- Ana Sofia Meza Herrera.
- Juan Carlos Narváez Castaño.
- Alejandro Villarreal Imitola.
