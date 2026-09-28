output "alb_dns_name" {
  description = "URL DNS del ALB de demostración (HTTP; no usar para producción)."
  value       = aws_lb.app.dns_name
}

output "private_instance_id" {
  description = "Instancia privada administrable por Session Manager si los endpoints y permisos están disponibles."
  value       = aws_instance.app.id
}

output "vpc_id" {
  description = "Identificador de la VPC del laboratorio."
  value       = aws_vpc.main.id
}

output "cloudtrail_bucket_name" {
  description = "Bucket de auditoría; se entrega solo si servicios de seguridad están habilitados."
  value       = try(aws_s3_bucket.trail[0].bucket, null)
}
