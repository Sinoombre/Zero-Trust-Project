# Proyecto 08 — Zero Trust y cumplimiento en AWS

**Paquete inicial para semanas 1–5.** La infraestructura está escrita como código; no significa que haya sido desplegada ni que el entorno obtenga un puntaje de cumplimiento. Para afirmar resultados, despliega en AWS Academy/Educate y adjunta evidencia real.

## Qué incluye

- Terraform: VPC con subredes públicas/privadas, EC2 privada sin IP pública, IMDSv2 obligatorio, acceso SSM sin SSH, ALB, WAFv2, GuardDuty, AWS Config, CloudTrail con validación de archivos, Security Hub y IAM Access Analyzer.
- Informe técnico y plantilla de evidencias.
- Runbook básico para respuesta y recuperación de acceso.
- Workflow de GitHub Actions para `terraform fmt` e `init/validate` (sin credenciales AWS ni despliegue automático).

## Requisitos y advertencias

- Terraform >= 1.5 y una cuenta **AWS Academy/Educate o sandbox autorizada**. No usar una cuenta personal de producción.
- Los servicios de AWS pueden generar costos. En cuentas compartidas, verifica con el administrador si GuardDuty, Config, Security Hub o Access Analyzer ya existen; AWS limita algunas de estas configuraciones por cuenta/región. No ejecutes `apply` sin revisar el presupuesto y el plan con tu docente. El NAT Gateway está desactivado por defecto; si se habilita (`enable_nat_gateway = true`) para que la instancia descargue paquetes, genera cargos por hora/GB. SSM usa endpoints privados que también pueden generar cargos.
- El ejemplo usa `us-east-1` por defecto; cámbialo solo si tu curso lo requiere. WAF y Security Hub generan cargos potenciales.
- La configuración crea infraestructura real si se ejecuta `terraform apply`. Este paquete no la ha desplegado.
- No hay listener HTTPS ni certificado TLS en este paquete: el ALB de demostración sirve HTTP. Para producción, configura ACM/HTTPS y redirección 80→443 antes de exponer un servicio.
- IAM Identity Center depende de la configuración de la cuenta/organización y se documenta como paso manual; no se activa automáticamente con este Terraform.

## Estructura

```text
terraform/       Infraestructura (semanas 1–5)
docs/informe.md  Informe listo para completar con evidencias reales
docs/arquitectura.md  Diagrama Mermaid de arquitectura
docs/runbook.md  Respuesta a incidentes y recuperación
.github/workflows/terraform.yml  Validación estática en GitHub Actions
```

## Validación local

```bash
cd terraform
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform plan -out=tfplan
```

Revisa `tfplan` y la estimación de costos antes de solicitar autorización para `terraform apply`. Nunca subas `terraform.tfstate`, `tfplan`, credenciales, claves ni tokens al repositorio.

## Validación realizada en este entorno

Con Terraform CLI 1.8.5 se ejecutaron `terraform fmt -check -recursive` y `terraform validate`: ambos finalizaron correctamente. Esto valida sintaxis y esquema del proveedor, pero no confirma permisos, costos ni comportamiento en una cuenta AWS; no se ejecutó `terraform plan` ni `apply`.

## Entrega académica honesta

1. Sube el contenido a un repositorio privado del equipo.
2. Completa `docs/informe.md` con nombres/roles del equipo, decisiones y capturas propias.
3. Incluye salidas de `terraform fmt`, `validate` y `plan` (oculta IDs/ARN si tu docente lo solicita).
4. Marca como **pendiente/no desplegado** cualquier control que no esté habilitado en la cuenta.
5. La evaluación pide además respuesta automática EventBridge→Lambda→SNS, runbook y presentación final (semanas 6–8); no afirmes que esas partes están implementadas por este starter.
