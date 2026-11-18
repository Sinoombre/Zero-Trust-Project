# Zero Trust en AWS - Runbook

Este runbook describe cómo desplegar, operar, monitorear, responder a incidentes y destruir el laboratorio Zero Trust.

## 1. Inventario de recursos

Los nombres salen de `var.project_name`.

> \[\!note\] Los marcados con `*` solo existen si `enable_security_services = true`.

| Componente        | Nombre / identificador                                                                                                                          | Archivo                |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| VPC               | `10.20.0.0/16`, 2 subredes públicas (`10.20.1.0/24`, `10.20.2.0/24`) y 2 privadas (`10.20.11.0/24`, `10.20.12.0/24`)                            | `network.tf`           |
| ALB               | `zero-trust-lab-alb` (público, protección contra borrado activa)                                                                                | `load_balancer.tf`     |
| Target group      | `zero-trust-lab-tg` (puerto 443, protocolo HTTPS)                                                                                               | `load_balancer.tf`     |
| WAFv2             | `zero-trust-lab-web-acl` (Common, SQLi, KnownBadInputs, IpReputation, rate limit 2000)                                                          | `waf.tf`               |
| EC2               | `zero-trust-lab-private-app`, `t3.micro`, subred privada 1, sin IP pública, IMDSv2 obligatorio                                                  | `compute.tf`           |
| Security groups   | `-alb-sg`, `-app-sg`, `-ssm-endpoints-sg`, `-empty-sg` (aislamiento), SG por defecto vaciado                                                    | `security_groups.tf`   |
| Lambda            | `zero-trust-lab-lambda-responder` (Python 3.13, timeout 30 s, dentro de la VPC)                                                                 | `incident_response.tf` |
| Regla EventBridge | `zero-trust-lab-guardduty-high-severity` (severidad ≥ 7)                                                                                        | `incident_response.tf` |
| SNS               | `zero-trust-lab-security-alerts` (cifrado con `alias/aws/sns`)                                                                                  | `incident_response.tf` |
| CloudTrail `*`    | `zero-trust-lab-trail` (multi-región, validación de integridad, KMS)                                                                            | `cloudtrail.tf`        |
| Log groups        | `/aws/cloudtrail/zero-trust-lab-trail` `*`, `/zero-trust-lab/vpc-flow-logs`, `/aws/lambda/zero-trust-lab-lambda-responder` (retención 365 días) | varios                 |
| Buckets S3        | `-logs-`, `-replication-`, `-config-` `*`, `-trail-` `*` (sufijo: cuenta + 4 bytes aleatorios)                                                  | `s3.tf`                |
| Claves KMS        | `alias/zero-trust-lab-s3`, `-cloudtrail` `*`, `-cw-logs`, `-lambda` (rotación activa, ventana de borrado 30 días)                               | varios                 |
| Presupuesto       | `zero-trust-lab-monthly` (alertas al 50 % y 100 % del gasto real)                                                                               | `budgets.tf`           |

Para obtener los identificadores reales después del despliegue:

bash

```bash
cd terraform
terraform output                       # alb_dns_name, private_instance_id, vpc_id, cloudtrail_bucket_name
terraform state list | head -100       # inventario completo gestionado por Terraform
```

## 2. Requisitos previos

| Requisito    | Detalle                                                                                                                                               |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Herramientas | Terraform ≥ 1.5.0, AWS CLI v2, plugin `session-manager-plugin`                                                                                        |
| Credenciales | Perfil con permisos para crear IAM, KMS, S3, EC2/VPC, ELB, WAFv2, Lambda, SNS, CloudTrail, Config, GuardDuty, Security Hub, Access Analyzer y Budgets |
| Región       | `us-east-2`. Si se cambia, se debería editar también `terraform/lambda/responder.py`                                                                  |
| Correo       | Un buzón real en `alert_email`: recibe alertas de SNS y de Budgets                                                                                    |
| Cuenta       | Cuenta de laboratorio dedicada                                                                                                                        |

Verificación rápida de identidad y región:

bash

```bash
aws sts get-caller-identity
aws configure get region
```

## 3. Despliegue

### 3.1 Primera vez

bash

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Editar: alert_email (obligatorio), budget_limit_usd, y los flags de costo
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

> \[\!note\]
>
> - El `archive_file` empaqueta `lambda/responder.py` en `lambda/responder.zip` (ignorado por git).
> - Hay un `time_sleep` de 10 s para esperar la propagación de la clave KMS de CloudTrail. Si aun así aparece "KMS Key Id could not be found", repite `terraform apply`.

### 3.2 Variables que cambian el comportamiento

| Variable                         | Defecto | Efecto operativo                                                                                      |
| -------------------------------- | ------- | ----------------------------------------------------------------------------------------------------- |
| `enable_security_services`       | `true`  | Crea CloudTrail, Config, GuardDuty, Security Hub, Access Analyzer y sus buckets/claves. Genera costos |
| `enable_ssm_interface_endpoints` | `true`  | Crea endpoints `ssm`, `ssmmessages`, `ec2messages`                                                    |
| `enable_ec2_interface_endpoint`  | `false` | Endpoint del servicio EC2                                                                             |
| `enable_nat_gateway`             | `false` | Crea NAT + rutas                                                                                      |
| `create_acm_certificate`         | `false` | Crea el certificado ACM y el listener HTTPS                                                           |
| `alb_deletion_protection`        | `true`  | Debe ponerse en `false` antes de destruir                                                             |
| `budget_limit_usd`               | `50`    | Tope mensual para las alertas                                                                         |

### 3.3 Validación posterior al despliegue (checklist)

| #   | Verificación                 | Comando / acción                                                           | Resultado esperado                                                 |
| --- | ---------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| 1   | Confirmar la suscripción SNS | Abrir el correo "AWS Notification - Subscription Confirmation" y confirmar | Estado `Confirmed`.                                                |
| 2   | Suscripción confirmada       | `aws sns list-subscriptions-by-topic --topic-arn <ARN>`                    | `SubscriptionArn` distinto de `PendingConfirmation`                |
| 3   | EC2 gestionada por SSM       | `aws ssm describe-instance-information`                                    | La instancia aparece con `PingStatus: Online` (tarda unos minutos) |
| 4   | Estado del target            |                                                                            |                                                                    |
| 5   | CloudTrail activo            | `aws cloudtrail get-trail-status --name zero-trust-lab-trail`              | `IsLogging: true`                                                  |
| 6   | Config grabando              | `aws configservice describe-configuration-recorder-status`                 | `recording: true`                                                  |
| 7   | GuardDuty activo             | `aws guardduty list-detectors`                                             | Un detector                                                        |
| 8   | Security Hub y estándar FSBP | `aws securityhub get-enabled-standards`                                    | FSBP v1.0.0 en `READY`                                             |
| 9   | Flow logs                    | `aws ec2 describe-flow-logs`                                               | Dos flow logs (S3 y CloudWatch) en `ACTIVE`                        |
| 10  | Prueba del responder         |                                                                            | Aislamiento + correo recibido                                      |
| 11  | Presupuesto                  | Consola de Budgets                                                         | `zero-trust-lab-monthly` con 2 alertas                             |

## 4. Operación diaria y periódica

### 4.1 Rutina

| Frecuencia                    | Tarea                                    | Cómo                                                                                                                                                                                                                     |
| ----------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Diaria (o antes de cada demo) | Revisar correos de SNS y de Budgets      | Buzón de `alert_email`                                                                                                                                                                                                   |
| Diaria                        | Hallazgos GuardDuty activos              | `aws guardduty list-findings --detector-id <ID> --finding-criteria '{"Criterion":{"service.archived":{"Eq":["false"]}}}'`                                                                                                |
| Semanal                       | Hallazgos críticos/altos en Security Hub | `aws securityhub get-findings --filters '{"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"},{"Value":"HIGH","Comparison":"EQUALS"}],"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}' --max-items 20` |
| Semanal                       | Cumplimiento de Config                   | `aws configservice describe-compliance-by-config-rule`                                                                                                                                                                   |
| Semanal                       | Hallazgos del Access Analyzer            | `aws accessanalyzer list-findings --analyzer-arn <ARN> --filter '{"status":{"eq":["ACTIVE"]}}'`                                                                                                                          |
| Por cambio                    | Drift de infraestructura                 | `terraform plan` debe salir sin cambios                                                                                                                                                                                  |
| Por cambio                    | Escaneo de seguridad                     | `checkov -d terraform --compact`                                                                                                                                                                                         |
| Mensual                       | Revisar costos                           | Cost Explorer, filtrado por la etiqueta `Project=zero-trust-lab`                                                                                                                                                         |
| Mensual                       | Revisar las excepciones `checkov:skip`   |                                                                                                                                                                                                                          |

### 4.2 Acceso administrativo a la instancia

No hay SSH ni IP pública.

El único canal es Session Manager.

bash

```bash
aws ssm start-session --target "$INSTANCE_ID"
```

Reglas de uso:

- Se debe usar solo cuando exista un motivo registrado (ticket, incidente o cambio).
- Cada sesión queda registrada en CloudTrail (`StartSession`), pero el contenido de la sesión no se registra: el repositorio no configura el registro de Session Manager hacia S3/CloudWatch.
- Si la instancia está aislada por el responder, Session Manager deja de funcionar (el SG vacío no permite el tráfico hacia los endpoints).

### 4.3 Cambios de infraestructura

1. Se debe crear una rama y un Pull Request. El CI ejecuta `terraform fmt -check`, `init -backend=false`, `validate` y el escaneo de Checkov.
2. Se debe ejecutar `terraform plan` local y una segunda persona debe revisar el diff.
3. `terraform apply` se debe ejecutar solo desde el equipo autorizado.
4. Si un cambio exige una nueva excepción `checkov:skip`, se debe documentar en la tabla del README con justificación y fecha de revisión.

> \[\!important\] Precaución en incidentes: si la instancia fue aislada por el responder, un `terraform apply` revertirá el aislamiento (Terraform restaurará `vpc_security_group_ids` a `-app-sg`). Se deben congelar los `apply` mientras haya un incidente abierto.

## 5. Procedimientos de mantenimiento

### 5.1 Actualizar o reemplazar la instancia

La instancia no tiene datos persistentes ni gestor de parches. El método soportado es reemplazarla:

bash

```bash
terraform -chdir=terraform apply -replace=aws_instance.app
```

La AMI se resuelve con `most_recent = true` (Amazon Linux 2023), por lo que cada reemplazo toma la AMI más reciente.

### 5.2 Actualizar la Lambda `responder`

Se debe editar `terraform/lambda/responder.py` y ejecutar `terraform apply`.

El hash del zip (`source_code_hash`) dispara el despliegue.

### 5.3 Rotación y claves

Las claves KMS tienen rotación anual automática.

> \[\!important\] No se pueden deshabilitar ni se puede programar su borrado. Afectan a los logs de CloudTrail, Config, flow logs y los buckets.

### 5.4 Habilitar HTTPS en el ALB

Hoy el listener HTTP:80 redirige a HTTPS:443, pero el listener 443 solo existe si `create_acm_certificate = true`.

Para HTTPS real:

1. Se debe tener un dominio propio y una zona en Route 53.
2. Se debe cambiar `domain_name` en `aws_acm_certificate.alb`.
3. Se debe agregar la validación DNS del certificado.
4. Se debe aplicar con `-var="create_acm_certificate=true"`.

### 5.5 Reactivar los access logs del ALB

Están desactivados (excepción `CKV_AWS_91`).

Tras el primer `apply`, se debe agregar el bloque `access_logs` al recurso `aws_lb.app`, apuntando a `aws_s3_bucket.logs` con prefijo `alb`. La política del bucket ya admite escrituras en `alb/AWSLogs/<cuenta>/*`.

### 5.6 Registro del WAF

El WAF no registra peticiones (excepción `CKV2_AWS_31`). Se debe configurar un destino (Firehose, S3 con prefijo `aws-waf-logs-` o CloudWatch Logs).

## 6. Respuesta a incidentes

### 6.1 Cómo funciona la automatización

Qué hace y qué no hace el responder:

| Hace                                                                                        | No hace                                        |
| ------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| Reemplaza los SG de la instancia afectada por el SG vacío (sin reglas de entrada ni salida) | No toma snapshot del disco, no captura memoria |
| Envía un correo con el estado, el tipo de hallazgo y la severidad                           | No detiene ni etiqueta la instancia            |
| Ignora hallazgos que no sean de tipo `Instance`                                             | No actúa sobre credenciales IAM, buckets, etc. |
| —                                                                                           | No corta conexiones ya establecidas            |
| —                                                                                           | No reacciona a hallazgos de severidad \< 7     |

## 7. Respaldo y recuperación

| Elemento                        | Respaldo                                           | Recuperación                                                                              |
| ------------------------------- | -------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Infraestructura                 | El código en Git                                   | `terraform apply` en una cuenta limpia                                                    |
| Estado de Terraform             | Ninguno automático (estado local)                  | Copiar manualmente fuera del repo; si se pierde, importar recursos con `terraform import` |
| Instancia EC2                   | Sin datos persistentes                             | Reemplazo con `-replace` (6.1)                                                            |
| Logs (CloudTrail, flow, Config) | Versionado + replicación a `-replication-` \[V\]   | Ver el aviso de replicación en 11.4                                                       |
| Retención de logs               | 365 días (reglas de ciclo de vida y de CloudWatch) | Exportar antes si se requiere más tiempo                                                  |

Objetivos propuestos para el laboratorio: RTO 4 h, RPO = el último commit (no hay datos de aplicación).

## 8. Destrucción del laboratorio

Orden recomendado:

1. Se deben congelar y exportar las evidencias que se necesiten conservar.
2. Se debe quitar la protección del ALB:
   bash
   ```bash
   cd terraform
   terraform apply -var="alb_deletion_protection=false"
   ```
3. Los buckets `-logs-`, `-trail-` y `-replication-` tienen `force_destroy = false` y versionado activo: `destroy` fallará si tienen objetos o versiones.
   Opciones: (a) Se debe poner `force_destroy = true` y aplicar antes de destruir.
   (b) Se deben vaciar con todas sus versiones. El bucket `-config-` ya tiene `force_destroy = true`.
4. Se debe ejecutar `terraform destroy`.
5. Las claves KMS quedan pendientes de borrado durante 30 días (siguen generando un costo mínimo) y los logs cifrados con ellas dejan de poder leerse al borrarse.
6. Efectos a nivel de cuenta al destruir: se retiran el bloqueo de acceso público de S3 de la cuenta, el cifrado de EBS por defecto, el bloqueo de snapshots y la política de contraseñas de IAM. En una cuenta compartida, esto afecta a otras cargas de trabajo.
7. Se debe verificar que no queden recursos de pago: ALB, NAT/EIP, endpoints de interfaz, detector de GuardDuty y grabador de Config.

## 9. Problemas conocidos y solución de fallos

Todos los puntos de esta sección derivan de la lectura del código y deben confirmarse en un despliegue real.

### 9.1 El target del ALB aparece `unhealthy`

- Causa probable: el target group usa puerto 443 y protocolo HTTPS, pero la instancia solo sirve HTTP en el 80 (instala `httpd` sin TLS), y el SG de la app solo admite el puerto 80 desde el ALB; el SG del ALB solo permite salida por el 80 hacia la VPC.
- Corrección: se debe cambiar el target group a `HTTP:80` (coherente con el SG `-app-sg`) o configurar TLS en la instancia y abrir el 443 entre el ALB y la aplicación.

### 9.2 La Lambda `responder` da `Task timed out`

- Causa probable: la Lambda está en subredes privadas con el SG vacío (sin salida) y no hay ruta privada a las API de EC2 ni de SNS por defecto (NAT desactivado, endpoint EC2 desactivado y endpoint de SNS inexistente).
- Corrección posible: se deben crear VPC endpoints de interfaz para `ec2` y `sns`, además de un SG que permita la salida por el puerto 443 hacia ellos para la Lambda. Como alternativa, se puede sacar la Lambda de la VPC (no necesita estar en ella para llamar a EC2/SNS y, de esta manera, también desaparecen los permisos de ENI).

### 9.3 El listener 80 redirige a un 443 que no responde

- Causa: sin `create_acm_certificate = true` no existe el listener 443 \[C\]. Actualmente, el ALB solo devuelve un `301` hacia un puerto cerrado. Ver 6.4.

### 9.4 Replicación S3 y avalancha de correos

- Los objetos cifrados con SSE-KMS no se replican, a menos que la configuración lo habilite explícitamente (criterio de selección de objetos KMS y clave de destino) y el rol de replicación tenga permisos de KMS. El repositorio no configura estos elementos.
- Los tres buckets (`-replication-`, `-config-`, `-trail-`) notifican cada objeto creado al topic SNS, que envía un correo. Por tanto, se espera un volumen alto de mensajes.
- El bucket de destino escribe sus logs de acceso en el bucket `-logs-`, que a su vez se replica al destino. Esto supone un riesgo de bucle de generación de logs y costos.
- El topic SNS está cifrado con la clave administrada `alias/aws/sns`. Los servicios que publican (S3, EventBridge y CloudWatch) suelen requerir una clave gestionada por el cliente.

### 9.5 La EC2 no descarga paquetes aunque se active el NAT

- El SG `-app-sg` solo permite salida por el puerto 443 hacia el CIDR de la VPC y hacia el prefijo de S3. No hay salida a `0.0.0.0/0` \[C\]. Activar `enable_nat_gateway` crea el NAT y las rutas, pero el SG sigue bloqueando el tráfico. El `dnf install httpd` del `user_data` funciona actualmente solo por el endpoint de S3 (los repositorios de Amazon Linux 2023 se sirven desde S3) \[V\].

### 9.6 Otros

| Síntoma                                       | Causa / acción                                                  |
| --------------------------------------------- | --------------------------------------------------------------- |
| `KMS Key Id could not be found` en CloudTrail | Consistencia eventual: se debe repetir `apply`                  |
| No llega ninguna alerta                       | Suscripción SNS en `PendingConfirmation`                        |
| Config/Security Hub sin datos                 | Se debe esperar el primer ciclo de evaluación (minutos a horas) |
| `terraform destroy` falla en el ALB           | Falta `alb_deletion_protection=false`                           |
| Falla de `terraform fmt -check` en CI         | Se debe ejecutar `terraform fmt -recursive`                     |
