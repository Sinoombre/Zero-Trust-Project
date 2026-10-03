# Security groups: 0.0.0.0/0 solo en el ALB, puertos 80 y 443

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "HTTP ingress to the demo ALB; HTTPS is reserved but no listener is configured."
  vpc_id      = aws_vpc.main.id
  ingress {
    description = "Demo HTTP endpoint"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS reserved; listener/certificate not provisioned"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "HTTP hacia destinos internos de la VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  tags = { Name = "${var.project_name}-alb-sg" }
}
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Application ingress only from the ALB. No SSH ingress."
  vpc_id      = aws_vpc.main.id
  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    description = "HTTPS hacia los endpoints de interfaz (SSM) dentro de la VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    description     = "HTTPS hacia S3 solo por el gateway endpoint (prefix list)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]
  }
  tags = { Name = "${var.project_name}-app-sg" }
}

resource "aws_security_group" "ssm_endpoints" {
  count       = var.enable_ssm_interface_endpoints ? 1 : 0
  name        = "${var.project_name}-ssm-endpoints-sg"
  description = "TLS from private VPC resources to Systems Manager endpoints."
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
  tags = { Name = "${var.project_name}-ssm-endpoints-sg" }
}

# SG por defecto de la VPC sin reglas
resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-default-sg-locked" }
}