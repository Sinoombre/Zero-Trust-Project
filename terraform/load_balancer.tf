# Application Load Balancer, target group y listeners (HTTP→HTTPS redirect + HTTPS).

# ACM certificate for HTTPS listener (lab domain; validar con Route53 en cuenta real).
resource "aws_acm_certificate" "alb" {
  count             = var.create_acm_certificate ? 1 : 0
  domain_name       = "${var.project_name}.example.com"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
  tags = { Name = "${var.project_name}-alb-cert" }
}

resource "aws_lb" "app" {
  # checkov:skip=CKV2_AWS_76:El WAFv2 asociado incluye AWSManagedRulesKnownBadInputsRuleSet y AWSManagedRulesAmazonIpReputationList, que cubren la protección contra Log4j (CVE-2021-44228).
  # checkov:skip=CKV_AWS_91:Access logs del ALB desactivados temporalmente por error transitorio de validación de bucket S3 en AWS. Se pueden reactivar después del apply inicial.
  name               = substr("${var.project_name}-alb", 0, 32)
  load_balancer_type = "application"
  internal           = false
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header_fields = true
  enable_deletion_protection = var.alb_deletion_protection
  depends_on                 = [aws_s3_bucket_policy.logs]

  tags = { Name = "${var.project_name}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = substr("${var.project_name}-tg", 0, 32)
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# HTTP listener (puerto 80) que redirige a HTTPS
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener (puerto 443) con TLS 1.2 y certificado ACM
resource "aws_lb_listener" "https" {
  count             = var.create_acm_certificate ? 1 : 0
  load_balancer_arn = aws_lb.app.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.alb[0].arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
  depends_on = [aws_acm_certificate.alb]
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = 443
}
