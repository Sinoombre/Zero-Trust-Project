variable "aws_region" {
  description = "Región del laboratorio. Confirma la región permitida por AWS Academy."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Prefijo para los recursos del proyecto."
  type        = string
  default     = "zero-trust-lab"
}

variable "environment" {
  description = "Etiqueta del entorno."
  type        = string
  default     = "academic"
}

variable "vpc_cidr" {
  description = "Bloque IPv4 de la VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Dos subredes públicas en AZ distintas (ALB)."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Se requieren exactamente dos CIDR de subred pública."
  }
}

variable "private_subnet_cidrs" {
  description = "Dos subredes privadas en AZ distintas (EC2 y endpoints)."
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Se requieren exactamente dos CIDR de subred privada."
  }
}

variable "enable_ssm_interface_endpoints" {
  description = "Crea endpoints privados SSM (pueden generar cargos)."
  type        = bool
  default     = true
}

variable "enable_security_services" {
  description = "Habilita servicios administrados con posibles cargos."
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Crea un NAT Gateway para que la instancia privada descargue paquetes. Tiene costo por hora y datos; dejar desactivado salvo autorización."
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Correo que recibe las alertas de AWS Budgets (50% y 100%). Ponlo en terraform.tfvars (ignorado por git)."
  type        = string
  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email debe ser una dirección de correo válida."
  }
}

variable "budget_limit_usd" {
  description = "Tope mensual en USD acordado con el docente (alertas al 50% y 100%)."
  type        = number
  default     = 50
}

variable "alb_deletion_protection" {
  description = "ELB.6. Para hacer terraform destroy primero aplica con false."
  type        = bool
  default     = true
}

variable "enable_ec2_interface_endpoint" {
  description = "Crea el endpoint de interfaz del servicio EC2 (control EC2.10). Genera cargos por hora y por AZ."
  type        = bool
  default     = false
}
