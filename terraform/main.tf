# Datos y recursos compartidos por varios archivos

data "aws_availability_zones" "available" {
  state      = "available"
  zone_names = ["${var.aws_region}a", "${var.aws_region}b"]
  # checkov:skip=CKV_AWS_394:Entorno de laboratorio; las zonas se asignan dinámicamente por AWS y no se conocen de antemano.
}

data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}