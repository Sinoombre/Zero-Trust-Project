# Zero Trust en AWS - Bitácora

> Para ver las evidencias por semana remitace al pdf

## Semana 1 (31 ago – 6 sep): Setup de cuenta, presupuesto, Terraform y repositorio

### ¿Qué se implementó?

- Repositorio GitHub del equipo con carpeta terraform/, .gitignore (excluye \*.tfstate, terraform.tfvars, llaves y evidencias) y workflow de GitHub Actions que ejecuta terraform fmt -check, init y validate en cada PR y push a main.
- Configuración base de Terraform (>= 1.5, provider AWS ~> 5.0, random ~> 3.6), región us-east-2 y default_tags (Project, ManagedBy, Environment) en todos los recursos.
- Variables parametrizadas con validaciones (CIDR, correo) y banderas de costo: enable_nat_gateway, enable_ssm_interface_endpoints, enable_ec2_interface_endpoint, enable_security_services.
- AWS Budgets mensual (budgets.tf) con notificaciones reales al 50 % y 100 % del tope (valor por defecto 50 USD, a confirmar con el docente).
- Roles IAM base en roles.tf: EC2 + Session Manager, AWS Config y VPC Flow Logs, con sufijo aleatorio (random_id) para evitar colisiones de nombres.
- Decisión de diseño: ningún aws_iam_user ni access key en el código; todo se autentica con roles por servicio.

### Amenaza que mitiga cada control

| **Control**                                                       | **Amenaza mitigada**                                                                                               |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Budgets al 50 % / 100 %                                           | Gasto descontrolado por recursos de seguridad que cobran por hora (NAT, endpoints de interfaz, Config, GuardDuty). |
| Roles IAM con trust policy por servicio (sin usuarios con claves) | Fuga o robo de credenciales de larga duración y su reutilización fuera de AWS.                                     |
| .gitignore de tfvars, tfstate y evidencias                        | Exposición de correo, ID de cuenta, ARNs o estado de Terraform en un repositorio compartido.                       |
| CI con fmt / validate                                             | Cambios sin revisar o con errores de sintaxis que lleguen a main.                                                  |

## Semana 2 (7 – 13 sep): Hardening de red, IMDSv2, endpoint S3 y Access Analyzer

### ¿Qué se implementó?

- VPC 10.20.0.0/16 con 2 subredes públicas (ALB) y 2 privadas (EC2 y endpoints) en dos zonas de disponibilidad, map_public_ip_on_launch = false incluso en las públicas.
- Tablas de ruta privadas sin salida a Internet; NAT Gateway opcional y apagado por defecto.
- VPC Endpoint de tipo Gateway para S3 asociado a las rutas privadas, y endpoints de interfaz para SSM (ssm, ssmmessages, ec2messages) con DNS privado y SG que solo acepta 443 desde la VPC.
- Security Groups: 0.0.0.0/0 únicamente en el ALB (80/443); la app solo recibe 80 desde el SG del ALB, sin ningún ingreso SSH, egress de la app limitado a 443 dentro de la VPC y a la prefix list de S3; SG por defecto de la VPC sin reglas.
- Instancia EC2 privada (t3.micro, Amazon Linux 2023): sin IP pública, IMDSv2 obligatorio (http_tokens = required, hop_limit = 1), disco raíz cifrado y administración por Session Manager.
- VPC Flow Logs (tráfico ALL) hacia S3 y hacia CloudWatch Logs (retención 365 días).
- IAM Access Analyzer de tipo cuenta (detection.tf).

### Amenaza que mitiga cada control

| Control                                       | Amenaza mitigada                                                                                                                                      |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sin IP pública + sin SSH + Session Manager    | Escaneo y fuerza bruta de SSH desde Internet; las sesiones SSM además quedan auditadas en CloudTrail.                                                 |
| IMDSv2 con hop limit 1                        | SSRF que roba las credenciales temporales del rol desde 169.254.169.254; el hop 1 evita que contenedores o proxies alcancen el servicio de metadatos. |
| SG de la app: solo origen ALB y egress mínimo | Movimiento lateral y exfiltración a Internet desde una instancia comprometida.                                                                        |
| SG por defecto vacío                          | Recursos nuevos que heredan reglas permisivas sin que nadie las haya revisado.                                                                        |
| Endpoint Gateway de S3                        | Tráfico hacia S3 saliendo por Internet público; permite además aplicar políticas de endpoint.                                                         |
| Flow Logs a S3 y CloudWatch                   | Falta de visibilidad forense: escaneos, tráfico anómalo o exfiltración sin rastro.                                                                    |
| Access Analyzer                               | Buckets, roles o claves compartidos accidentalmente con cuentas externas.                                                                             |
| Cifrado EBS                                   | Lectura de volúmenes o snapshots expuestos.                                                                                                           |

## Semana 3 (14 – 20 sep): WAFv2 con reglas OWASP sobre el ALB

### ¿Qué se implementó?

- Application Load Balancer público en las subredes públicas, con drop_invalid_header_fields, protección contra borrado (control ELB.6) y access logs hacia el bucket central de logs.
- Target group HTTP con health check en / y listener en el puerto 80 que reenvía a la instancia privada.
- Web ACL regional zero-trust-lab-web-acl (acción por defecto: allow) con tres reglas: AWSManagedRulesCommonRuleSet (prioridad 10; incluye las reglas de XSS), AWSManagedRulesSQLiRuleSet (prioridad 20) y RateLimit (prioridad 30, bloquea IP con más de 2000 solicitudes por ventana de 5 minutos).
- Métricas de CloudWatch y muestreo de solicitudes activados en el ACL y en cada regla; asociación del ACL al ALB.
- Decisión documentada: el ALB atiende solo HTTP porque no hay dominio ni certificado ACM; el puerto 443 está abierto en el SG pero sin listener (riesgo aceptado para el laboratorio).

### Amenaza que mitiga cada control

| Control                                | Amenaza mitigada                                                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Common Rule Set (XSS, LFI, bad inputs) | Ataques A03 de OWASP Top 10 y vulnerabilidades web comunes que roban sesiones o ejecutan código en el navegador. |
| SQLi Rule Set                          | Inyección SQL contra la aplicación que atraviesa el ALB.                                                         |
| Rate limit por IP                      | Denegación de servicio en capa 7, fuerza bruta y scraping agresivo.                                              |
| drop_invalid_header_fields             | Ataques de desincronización HTTP (request smuggling) con cabeceras malformadas.                                  |
| Access logs del ALB a S3               | Investigación posterior de qué IP pidió qué y cuándo.                                                            |
| Deletion protection (ELB.6)            | Borrado accidental o malicioso del punto de entrada.                                                             |

## Semana 4 (21 – 27 sep): GuardDuty y AWS Config (reglas managed)

### ¿Qué se implementó?

- GuardDuty habilitado con publicación de findings cada 15 minutos y la característica S3 Protection (S3_DATA_EVENTS) activada.
- AWS Config con recorder para todos los tipos soportados (sin tipos globales), canal de entrega a un bucket dedicado y recorder en estado habilitado.
- Cinco reglas managed: ec2-instances-in-vpc, ec2-instance-no-public-ip, s3-bucket-public-read-prohibited, root-account-mfa-enabled y restricted-ssh (identificador INCOMING_SSH_DISABLED). Las cuatro exigidas por el enunciado más ec2-instance-no-public-ip; la regla ec2-instances-in-vpc se incorporó en el commit del 3 de octubre.
- Verificación por CLI del detector de GuardDuty (la salida de get-detector quedó guardada, ver sección 6).

### Amenaza que mitiga cada control

| Control                                                  | Amenaza mitigada                                                                                                    |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| GuardDuty (CloudTrail, DNS, Flow Logs, S3)               | Instancias o credenciales comprometidas, tráfico a comandos y control, minería de criptomonedas y accesos anómalos. |
| S3 Protection                                            | Exfiltración o acceso inusual a datos en buckets (eventos de datos de S3).                                          |
| Config: restricted-ssh                                   | Alguien abre el puerto 22 a Internet desde la consola, rompiendo el diseño sin Terraform (drift).                   |
| Config: ec2-instance-no-public-ip y ec2-instances-in-vpc | Instancias creadas fuera de la VPC o con IP pública.                                                                |
| Config: s3-bucket-public-read-prohibited                 | Buckets legibles públicamente.                                                                                      |
| Config: root-account-mfa-enabled                         | Compromiso de la cuenta raíz sin segundo factor.                                                                    |
| Historial del recorder                                   | Imposibilidad de saber qué cambió y quién lo cambió.                                                                |

## Semana 5 (28 sep – 4 oct): CloudTrail (single-region) y Security Hub (FSBP)

### ¿Qué se implementó?

- Trail zero-trust-lab-trail de una sola región, con eventos de servicios globales y log file validation habilitada, entregando a un bucket de auditoría dedicado.
- Buckets de logs, Config y CloudTrail con el mismo patrón de seguridad: bloqueo de acceso público, cifrado SSE-S3, política que deniega transporte sin TLS, server access logging, ciclo de vida de 365 días y política restringida por servicio (aws:SourceArn / aws:SourceAccount).
- Security Hub activado con los estándares por defecto desactivados y suscripción explícita al estándar AWS Foundational Security Best Practices v1.0.0.
- Controles de cuenta en account_hardening.tf: bloqueo de acceso público de S3 a nivel de cuenta, cifrado EBS por defecto, bloqueo de compartición pública de snapshots, bloqueo de documentos SSM públicos y política de contraseñas (14 caracteres, rotación a 90 días, 24 reutilizaciones).
- Reorganización del código (3 de octubre): el main.tf monolítico (~490 líneas) y hardening.tf se dividieron en archivos por tema; se agregó la carpeta docs/, se actualizó el README y se adelantó el rol IAM del Lambda Responder (semana 6).

### Amenaza que mitiga cada control

| Control                                                        | Amenaza mitigada                                                                            |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Log file validation (digest firmado)                           | Manipulación o borrado de logs para ocultar actividad (anti-forense).                       |
| Políticas de bucket con aws:SourceArn                          | Ataque “confused deputy”: que otro trail o servicio escriba en nuestro bucket de auditoría. |
| Denegar transporte sin TLS                                     | Intercepción o alteración de logs en tránsito.                                              |
| Security Hub + FSBP                                            | Desviaciones de buenas prácticas sin una vista única de cumplimiento y priorización.        |
| Bloqueo de acceso público a nivel de cuenta y de snapshots EBS | Exposición pública accidental de datos, aunque un bucket individual se configure mal.       |
| Política de contraseñas y cifrado EBS por defecto              | Credenciales débiles y volúmenes nuevos sin cifrar.                                         |

Para la calificación de AWS FSBP, se tenía una meta inicial de por encima del 80% (lo mínimo requerido), por tanto, hemos excedido en la realización de esta tarea, y se debe tener en cuenta que algunos errores deben ser documentados como excepciones, ya que son errores a propósito (por decisiones de diseño en el desarrollo del programa que AWS FSBP marca como errores).

## Semana 6 (5 oct – 12 oct): EventBridge rules, Lambda responder, SNS alertas

### ¿Qué se implementó?

- Topic SNS security-alerts cifrado en reposo con KMS (aws/sns), con suscripción por correo electrónico al destinatario de alertas (var.alert_email).
- Función Lambda lambda-responder (Python 3.13), empaquetada como ZIP, desplegada en subnets privadas con security group restringido, timeout de 30 segundos, 5 ejecuciones concurrentes reservadas, tracing activo (X-Ray) y dead-letter queue apuntando al topic SNS para no perder eventos de respuesta.
- Rol IAM lambda-responder con política de mínimo privilegio: escritura de sus propios logs en CloudWatch, ec2:DescribeInstances/ec2:DescribeSecurityGroups, ec2:ModifyInstanceAttribute para reemplazar los security groups de una instancia por el security group vacío (aislamiento), y sns:Publish exclusivo al topic de alertas.
- Regla EventBridge guardduty-high-severity que filtra eventos de GuardDuty (aws.guardduty, GuardDuty Finding) con severidad numérica >= 7 (HIGH o superior) e invoca como target la función Lambda Responder.
- Permiso de invocación lambda:InvokeFunction para events.amazonaws.com restringido por source_arn a la regla EventBridge (evita confused deputy).
- Log group de CloudWatch /aws/lambda/<proyecto>-lambda-responder con retención de 365 días y cifrado con KMS.
- Clave KMS dedicada para cifrar variables de entorno de la Lambda y el log group, con rotación habilitada.

### Amenaza que mitiga cada control

| Control                                                                   | Amenaza mitigada                                                                                                                        |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Regla EventBrdige con filtro de severidad >= 7                            | Alerta fatiga: solo se activa respuesta entre hallazgos críticos (GuardDuty HIGH o superior)                                            |
| Lambda Responder con el rol de mínimo privilegio                          | Compromiso o abuso de credenciales de la función. Solo puede aislar instancias, leer estado de EC2, escribir sus logs y publicar en SNS |
| Aislamiento de instancia (ModifyInstanceAttribute y security Group vacío) | Movimiento lateral de un atacante desde una instancia comprometida. Se corta su conectividad de red de inmediato.                       |
| Topic SNS cifrado con KMS y suscripción por email                         | Exposición o pérdida de alertas de seguridad. Notificación cifrada y directa al equipo de respuesta.                                    |
| Dead-letter queue de Lambda en SNS                                        | Pérdida de eventos de respuesta cuando falla la invocación de la Lambda                                                                 |
| Log Group con retención 365 días y cifrado MS                             | Borrado o manipulación de evidencias de las acciones de respuesta automática (anti-forense).                                            |
| Permiso de EventBridge restringido por source_arn                         | Ataque “confused deputy”: otro servicio o regla invocando la Lambda Responder.                                                          |

## Semana 7 (12 oct – 19 oct): Configuración de checkov

### ¿Qué se implementó?

- Escaneo automatizado de seguridad estática con Checkov en el pipeline de GitHub Actions (.github/workflows/checkov.yml), que se dispara en cada push y pull request sobre cualquier rama cuando hay cambios en terraform/, usando bridgecrewio/checkov-action@v12 contra el framework Terraform del directorio terraform/ con salida en formato CLI.
- Resultados del escaneo con checkov -d terraform --compact: 247 checks PASSED, 7 SKIPPED y 0 FAILED.
- Reducción de 38 checks fallidos iniciales (distribuidos en 11 archivos de Terraform) a 0 fallos, corrigiendo los problemas o documentándolos con supresiones inline checkov:skip acompañadas de justificación técnica.
- No se utilizó un archivo .checkovignore; todas las excepciones se declararon de forma explícita y localizada junto al recurso correspondiente.
- Supresiones inline documentadas por recurso:
  - CKV_AWS_252 en cloudtrail.tf (CloudTrail): sns_topic_arn es computed por el uso de count y Checkov no resuelve referencias cruzadas entre archivos.
  - CKV_AWS_272 en incident_response.tf (Lambda responder): falta code signing de AWS Signer, cuyo signing profile no está disponible en el laboratorio de una sola cuenta.
  - CKV_AWS_173 en incident_response.tf (Lambda responder): kms_key_arn en el bloque environment no es soportado por la versión del provider AWS usado.
  - CKV_AWS_394 en main.tf (availability zones): entorno de una sola cuenta; las zonas se asignan dinámicamente por AWS.
  - CKV_AWS_260 en security_groups.tf (Security Group del ALB): el ALB debe recibir HTTP 0.0.0.0/0:80 para poder redirigir a HTTPS mediante el listener de redirect.
  - CKV2_AWS_76 en load_balancer.tf (ALB): el WAFv2 asociado incluye AWSManagedRulesKnownBadInputsRuleSet y AWSManagedRulesAmazonIpReputationList, que cubren protección contra Log4j (CVE-2021-44228).
  - CKV2_AWS_3 en detection.tf (GuardDuty): laboratorio de una sola cuenta; el bloque data_source no es soportado por la versión del provider.

### Amenaza que mitiga cada control

| Control                                            | Amenaza mitigada                                                                                       |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Escaneo Checkov en CI/CD (PR y push)               | Desviaciones de seguridad introducidas sin revisión en cambios de infraestructura                      |
| 0 checks FAILED y 247 PASSED                       | Recursos desplegados con configuraciones inseguras que pudieran exponer datos o superficies de ataque. |
| Supresiones checkov:skip con justificación técnica | Excepciones ocultas o no documentadas que debilitan el modelo de seguridad sin trazabilidad.           |
| Ausencia de .checokvignore                         | Excepciones globales difíciles de auditar. Se prefieren supresiones inline localizadas por recurso     |
| Justificaciones documentadas por check ID          | Decisiones de riesgo aceptado sin contexto, dificultando la revisión y aprobación por seguridad        |
