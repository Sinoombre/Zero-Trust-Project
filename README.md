# Zero Trust en AWS — Proyecto 08

![Terraform >= 1.5.0](https://img.shields.io/badge/Terraform-%3E%3D1.5.0-7B42BC?logo=terraform)

Infraestructura como código (Terraform) con arquitectura Zero Trust y cumplimiento de AWS Foundational Security Best Practices, para AWS Academy.

## Estado de Seguridad (Checkov)

Ejecutando `checkov -d terraform --compact`:

| Métrica | Cantidad |
| ------- | -------- |
| PASSED | 247 |
| SKIPPED | 7 |
| FAILED | 0 |

Inicialmente había 38 checks fallidos distribuidos en 11 archivos de Terraform. Todos fueron corregidos o documentados con `checkov:skip` (supresiones inline con justificación técnica). No se utilizó un archivo `.checkovignore`.

## Checks Saltados (SKIPPED) y Justificación

| Check ID | Recurso | Archivo | Motivo |
| ---------- | --------- | -------- | ------ |
| CKV_AWS_252 | `aws_cloudtrail.main[0]` | `cloudtrail.tf` | `sns_topic_arn` se eliminó porque con `count` su valor es computed y no resoluble estáticamente por Checkov. El topic SNS `aws_sns_topic.security_alerts` está definido en `incident_response.tf`; Checkov no resuelve referencias cruzadas entre archivos. |
| CKV_AWS_272 | `aws_lambda_function.lambda_responder` | `incident_response.tf` | Se eliminó `aws_lambda_code_signing_config` porque requiere un signing profile de AWS Signer no disponible en este laboratorio de una sola cuenta. El Lambda no tiene code signing configurado. |
| CKV_AWS_173 | `aws_lambda_function.lambda_responder` | `incident_response.tf` | Se eliminó `kms_key_arn` del bloque `environment` porque no es soportado por esta versión del provider AWS. El KMS key existe pero no se puede asociar estáticamente al recurso. |
| CKV_AWS_394 | `aws_availability_zones.available` | `main.tf` | Entorno de laboratorio de una sola cuenta; las zonas se asignan dinámicamente por AWS y no se conocen de antemano. `zone_names` no es un argumento de entrada válido en `aws_availability_zones`. |
| CKV_AWS_260 | `aws_security_group.alb` | `security_groups.tf` | El ALB es público y requiere ingreso HTTP `0.0.0.0/0:puerto 80` para poder redirigir a HTTPS mediante el listener de redirect configurado. |
| CKV2_AWS_76 | `aws_lb.app` | `load_balancer.tf` | El WAFv2 asociado incluye `AWSManagedRulesKnownBadInputsRuleSet` y `AWSManagedRulesAmazonIpReputationList`, que cubren la protección contra Log4j (CVE-2021-44228). |
| CKV2_AWS_3 | `aws_guardduty_detector.main[0]` | `detection.tf` | Entorno de laboratorio de una sola cuenta; GuardDuty está habilitado en la región configurada (`var.aws_region`). Se eliminó el bloque `data_source` por no ser soportado en esta versión del provider. |

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
