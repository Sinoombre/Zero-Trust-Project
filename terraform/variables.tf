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
