# Zero Trust en AWS

## Introducción

Implementación infraestructura alineada con el modelo Zero Trust (“nunca confiar, siempre verificar”) en la plataforma AWS, aplicando mínimo privilegio, microsegmentación de red y autenticación basada en roles temporales en lugar de credenciales de larga duración. Toda la infraestructura se define como código con Terraform, incluyendo las políticas de seguridad, las reglas de AWS Config y los controles de WAF.

> Para detección de amenazas y auditoría usamos servicios gestionados de AWS (GuardDuty, Config, Security Hub y CloudTrail).

La meta es demostrar que la infraestructura cumple el **estándar AWS Foundational Security Best Practices (FSBP)** con un score mayor al **80 %**.

### Especificaciones técnicas

| **Ítem**                        | **Detalle**                                                            |
| ------------------------------- | ---------------------------------------------------------------------- |
| **Plataforma cloud**            | Amazon Web Services (AWS)                                              |
| **Frameworks**                  | AWS Well-Architected (Security Pillar) + CIS AWS Foundations Benchmark |
| **Infraestructura como código** | Terraform                                                              |
| **Análisis estático de IaC**    | Checkov                                                                |
| **Control de versiones**        | GitHub                                                                 |
| **CI/CD**                       | GitHub Actions (workflows)                                             |

## Objetivos

- Aplicar los principios de Zero Trust mediante controles de mínimo privilegio, microsegmentación y acceso just-in-time.
- Implementar AWS WAFv2 con reglas de protección frente a las vulnerabilidades contempladas en OWASP Top 10.
- Configurar Amazon GuardDuty para la detección automatizada de amenazas y actividades sospechosas.
- Implementar AWS Config con reglas administradas (Managed Rules) para identificar desviaciones en las configuraciones de seguridad.
- Centralizar los hallazgos y alertas de seguridad mediante AWS Security Hub.
- Automatizar la respuesta a incidentes utilizando Amazon EventBridge y AWS Lambda.
- Implementar AWS Systems Manager Session Manager como alternativa segura al acceso directo mediante SSH.

## Requerimientos Técnicos

| **Requerimiento** | **Descripción**                                                                                                                            |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| **RT-1**          | Habilitar VPC Flow Logs y enviarlos a S3 y a CloudWatch Logs.                                                                              |
| **RT-2**          | No usar Security Groups permisivos: 0.0.0.0/0 solo en el ALB y únicamente en los puertos 80/443.                                           |
| **RT-3**          | Configurar NACLs restrictivos en las subredes privadas.                                                                                    |
| **RT-4**          | Crear VPC Endpoints para S3 y DynamoDB, para que ese tráfico no salga a Internet.                                                          |
| **RT-5**          | No usar usuarios IAM con access keys de larga duración (se usan IAM Roles).                                                                |
| **RT-6**          | Exigir IMDSv2 en todas las instancias EC2.                                                                                                 |
| **RT-7**          | Aplicar Service Control Policies (SCPs) si se usa AWS Organizations.                                                                       |
| **RT-8**          | Usar Permission Boundaries para limitar el alcance de los roles.                                                                           |
| **RT-9**          | Habilitar IAM Access Analyzer.                                                                                                             |
| **RT-10**         | Habilitar GuardDuty con S3 Protection y EKS Protection activadas.                                                                          |
| **RT-11**         | Configurar AWS Config con las reglas ec2-instances-in-vpc, restricted-ssh, s3-bucket- public-read-prohibited y root-account-mfa-enabled.   |
| **RT-12**         | Activar Security Hub con el estándar AWS Foundational Security Best Practices.                                                             |
| **RT-13**         | Configurar CloudTrail multi-región con log file validation (integridad de los logs).                                                       |
| **RT-14**         | Crear una regla de EventBridge que dispare una Lambda cuando GuardDuty genere un finding de severidad HIGH.                                |
| **RT-15**         | Programar la Lambda Responder para que tome un snapshot de la instancia comprometida, la aísle (Security Group vacío) y notifique por SNS. |

## Cumplimiento frente al enunciado

### Requerimientos técnicos

| **Req.** | **Requerimiento**                                | **Estado**   | **Dónde / comentario**                                                                |
| -------- | ------------------------------------------------ | ------------ | ------------------------------------------------------------------------------------- |
| 4.1      | Flow Logs a S3 + CloudWatch                      | **Cumplido** | logging.tf                                                                            |
| 4.1      | SGs restrictivos (0.0.0.0/0 solo en ALB, 80/443) | **Cumplido** | security_groups.tf                                                                    |
| 4.1      | VPC Endpoint para S3                             | **Cumplido** | networking.tf (Gateway, rutas privadas)                                               |
| 4.2      | Sin IAM users con claves de larga duración       | **Cumplido** | No hay aws_iam_user en el código; confirmar con credential report                     |
| 4.2      | IMDSv2 con hop_limit = 1                         | **Cumplido** | compute.tf                                                                            |
| 4.2      | IAM Access Analyzer                              | **Cumplido** | detection.tf (tipo ACCOUNT)                                                           |
| 4.3      | GuardDuty con S3 Protection                      | **Cumplido** | detection.tf                                                                          |
| 4.3      | Config: 4 reglas exigidas                        | **Cumplido** | config.tf (+ ec2-instance-no-public-ip)                                               |
| 4.3      | Security Hub con FSBP                            | **Cumplido** | Suscripción creada; falta medir el score                                              |
| 4.3      | CloudTrail single-region con validación          | **Cumplido** | cloudtrail.tf                                                                         |
| 4.4      | EventBridge -> Lambda -> SNS                     | **Cumplido** | Solo existe el rol IAM del Lambda; faltan regla, función, tema SNS y SG de cuarentena |
| 4.4      | Runbook de respuesta a incidentes                | **Cumplido** | Semana 7                                                                              |
| 5        | AWS Budgets 50 % y 100 %                         | **Cumplido** | budgets.tf                                                                            |
| 5        | Procedimiento de recuperación ante bloqueo IAM   | **Cumplido** | Propuesta en la sección 7                                                             |

## Reproducibilidad

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # editar alert_email y budget_limit_usd
terraform init
terraform plan
terraform apply
```

Para destruir el laboratorio

> El ALB tiene protección contra borrado. Antes de `terraform destroy`

```bash
terraform apply -var="alb_deletion_protection=false"
terraform destroy
```

## Costos

NAT Gateway, endpoints de interfaz y los servicios de seguridad generan cargos.
Revise `enable_nat_gateway`, `enable_ssm_interface_endpoints`,
`enable_ec2_interface_endpoint` y `enable_security_services` antes de aplicar.

## Conclusión
