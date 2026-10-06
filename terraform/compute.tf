# Instancia de aplicación en subred privada (sin IP pública, IMDSv2, administrada por SSM).
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = false
  user_data                   = <<-USERDATA
    #!/bin/bash
    dnf install -y httpd
    systemctl enable --now httpd
    echo '<h1>Zero Trust AWS lab</h1><p>Demo instance: private subnet; administer via Session Manager.</p>' > /var/www/html/index.html
  USERDATA
  # IMDSv2: obligar a que las aplicaciones usen tokens de sesión para acceder a los metadatos de la instancia.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    encrypted = true
  }
  tags = { Name = "${var.project_name}-private-app" }
}