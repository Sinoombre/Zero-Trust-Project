# Zero Trust en AWS — Proyecto 08

Infraestructura como código (Terraform) con arquitectura Zero Trust y cumplimiento de AWS Foundational Security Best Practices, para AWS Academy.

## Estructura

```
.
├── .github/workflows/terraform.yml   # fmt, validate y tflint en cada PR
├── docs/                             # runbook, threat model (evidencias/ no se versiona)
└── terraform/
    ├── versions.tf                   # versiones de Terraform y providers
    ├── providers.tf                  # provider AWS y default_tags
    ├── variables.tf
    ├── outputs.tf
    ├── main.tf                       # datos compartidos y sufijo aleatorio
    ├── network.tf                    # VPC, subredes, NAT opcional, VPC endpoints
    ├── security_groups.tf            # SGs (0.0.0.0/0 solo en el ALB)
    ├── compute.tf                    # EC2 privada (IMDSv2, sin IP pública)
    ├── load_balancer.tf              # ALB
    ├── waf.tf                        # WAFv2: OWASP + rate limit
    ├── roles.tf                      # todos los roles IAM
    ├── s3.tf                         # todos los buckets (logs, config, trail)
    ├── logging.tf                    # VPC Flow Logs
    ├── config.tf                     # AWS Config y reglas managed
    ├── cloudtrail.tf                 # CloudTrail 
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
Revisa `enable_nat_gateway`, `enable_ssm_interface_endpoints`,
`enable_ec2_interface_endpoint` y `enable_security_services` antes de aplicar.

## Equipo

**Firmes por Palmer**
- Mario Alberto Julio Wilches.
- Ana Sofia Meza Herrera.
- Juan Carlos Narvaez Castaño.
- Alejandro Villarreal Imitola.
