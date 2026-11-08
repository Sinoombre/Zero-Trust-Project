# Zero Trust en AWS — Checkov

Con el objetivo de fortalecer la seguridad de la infraestructura de la instancia, se integró [Checkov](https://github.com/Sinoombre/Zero-Trust-Project/blob/main/.github/workflows/checkov.yml), una herramienta de análisis estático de infraestructura como código (IaC), mediante un workflow que permite identificar posibles vulnerabilidades y configuraciones inseguras durante el proceso de integración continua (CI).

## Estado de Seguridad (Checkov)

Ejecutando `checkov -d terraform --compact`:

| Métrica | Cantidad |
| ------- | -------- |
| PASSED  | 247      |
| SKIPPED | 7        |
| FAILED  | 0        |

Inicialmente había 38 checks fallidos distribuidos en 11 archivos de Terraform. Todos fueron corregidos o documentados con `checkov:skip` (supresiones inline con justificación técnica). No se utilizó un archivo `.checkovignore`.

## Checks Saltados (SKIPPED) y Justificación

| Check ID    | Recurso                                | Archivo                | Motivo                                                                                                                                                                                                                                                      |
| ----------- | -------------------------------------- | ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CKV_AWS_252 | `aws_cloudtrail.main[0]`               | `cloudtrail.tf`        | `sns_topic_arn` se eliminó porque con `count` su valor es computed y no resoluble estáticamente por Checkov. El topic SNS `aws_sns_topic.security_alerts` está definido en `incident_response.tf`; Checkov no resuelve referencias cruzadas entre archivos. |
| CKV_AWS_272 | `aws_lambda_function.lambda_responder` | `incident_response.tf` | Se eliminó `aws_lambda_code_signing_config` porque requiere un signing profile de AWS Signer no disponible en este laboratorio de una sola cuenta. El Lambda no tiene code signing configurado.                                                             |
| CKV_AWS_173 | `aws_lambda_function.lambda_responder` | `incident_response.tf` | Se eliminó `kms_key_arn` del bloque `environment` porque no es soportado por esta versión del provider AWS. El KMS key existe pero no se puede asociar estáticamente al recurso.                                                                            |
| CKV_AWS_394 | `aws_availability_zones.available`     | `main.tf`              | Entorno de laboratorio de una sola cuenta; las zonas se asignan dinámicamente por AWS y no se conocen de antemano. `zone_names` no es un argumento de entrada válido en `aws_availability_zones`.                                                           |
| CKV_AWS_260 | `aws_security_group.alb`               | `security_groups.tf`   | El ALB es público y requiere ingreso HTTP `0.0.0.0/0:puerto 80` para poder redirigir a HTTPS mediante el listener de redirect configurado.                                                                                                                  |
| CKV2_AWS_76 | `aws_lb.app`                           | `load_balancer.tf`     | El WAFv2 asociado incluye `AWSManagedRulesKnownBadInputsRuleSet` y `AWSManagedRulesAmazonIpReputationList`, que cubren la protección contra Log4j (CVE-2021-44228).                                                                                         |
| CKV2_AWS_3  | `aws_guardduty_detector.main[0]`       | `detection.tf`         | Entorno de laboratorio de una sola cuenta; GuardDuty está habilitado en la región configurada (`var.aws_region`). Se eliminó el bloque `data_source` por no ser soportado en esta versión del provider.                                                     |
