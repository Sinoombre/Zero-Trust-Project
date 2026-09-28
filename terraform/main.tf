data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
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
resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-public-${count.index + 1}" }
}
resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-private-${count.index + 1}" }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rt-${count.index + 1}" }
}
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat-eip" }
}
resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "${var.project_name}-nat" }
}
resource "aws_route" "private_nat" {
  count                  = var.enable_nat_gateway ? 2 : 0
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[0].id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
  tags              = { Name = "${var.project_name}-s3-endpoint" }
}

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
    description = "HTTPS egress for AWS service endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
resource "aws_vpc_endpoint" "ssm" {
  for_each            = var.enable_ssm_interface_endpoints ? toset(["ssm", "ssmmessages", "ec2messages"]) : toset([])
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.ssm_endpoints[0].id]
  private_dns_enabled = true
  tags                = { Name = "${var.project_name}-${each.key}-endpoint" }
}

resource "aws_lb" "app" {
  name               = substr("${var.project_name}-alb", 0, 32)
  load_balancer_type = "application"
  internal           = false
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]
  tags               = { Name = "${var.project_name}-alb" }
}
resource "aws_lb_target_group" "app" {
  name        = substr("${var.project_name}-tg", 0, 32)
  port        = 80
  protocol    = "HTTP"
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
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-instance-profile-${random_id.suffix.hex}"
  role = aws_iam_role.ec2_ssm.name
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
resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = 80
}

resource "aws_wafv2_web_acl" "alb" {
  name        = "${var.project_name}-web-acl"
  description = "Managed OWASP protections and rate limit for the demo ALB."
  scope       = "REGIONAL"
  default_action {
    allow {}
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-web-acl"
    sampled_requests_enabled   = true
  }
  rule {
    name     = "AWSManagedCommonRuleSet"
    priority = 10
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common-rules"
      sampled_requests_enabled   = true
    }
  }
  rule {
    name     = "AWSManagedSQLiRuleSet"
    priority = 20
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "sqli-rules"
      sampled_requests_enabled   = true
    }
  }
  rule {
    name     = "RateLimit"
    priority = 30
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }
}
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
}

resource "aws_guardduty_detector" "main" {
  count                        = var.enable_security_services ? 1 : 0
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}
resource "aws_guardduty_detector_feature" "s3_protection" {
  count       = var.enable_security_services ? 1 : 0
  detector_id = aws_guardduty_detector.main[0].id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

resource "aws_iam_role" "config" {
  count = var.enable_security_services ? 1 : 0
  name  = "${var.project_name}-config-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "config.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "config" {
  count      = var.enable_security_services ? 1 : 0
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}
resource "aws_s3_bucket" "config" {
  count         = var.enable_security_services ? 1 : 0
  bucket        = "${var.project_name}-config-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "config" {
  count                   = var.enable_security_services ? 1 : 0
  bucket                  = aws_s3_bucket.config[0].id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  count  = var.enable_security_services ? 1 : 0
  bucket = aws_s3_bucket.config[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "config" {
  count  = var.enable_security_services ? 1 : 0
  bucket = aws_s3_bucket.config[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "AWSConfigBucketPermissionsCheck", Effect = "Allow", Principal = { Service = "config.amazonaws.com" }, Action = ["s3:GetBucketAcl", "s3:ListBucket"], Resource = aws_s3_bucket.config[0].arn },
      { Sid = "AWSConfigBucketDelivery", Effect = "Allow", Principal = { Service = "config.amazonaws.com" }, Action = "s3:PutObject", Resource = "${aws_s3_bucket.config[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*", Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } } }
    ]
  })
}
resource "aws_config_configuration_recorder" "main" {
  count    = var.enable_security_services ? 1 : 0
  name     = "${var.project_name}-recorder"
  role_arn = aws_iam_role.config[0].arn
  recording_group {
    all_supported                 = true
    include_global_resource_types = false
  }
}
resource "aws_config_delivery_channel" "main" {
  count          = var.enable_security_services ? 1 : 0
  name           = "${var.project_name}-delivery"
  s3_bucket_name = aws_s3_bucket.config[0].bucket
  depends_on     = [aws_s3_bucket_policy.config]
}
resource "aws_config_configuration_recorder_status" "main" {
  count      = var.enable_security_services ? 1 : 0
  name       = aws_config_configuration_recorder.main[0].name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}
resource "aws_config_config_rule" "ec2_no_public_ip" {
  count = var.enable_security_services ? 1 : 0
  name  = "ec2-instance-no-public-ip"
  source {
    owner             = "AWS"
    source_identifier = "EC2_INSTANCE_NO_PUBLIC_IP"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}
resource "aws_config_config_rule" "s3_public_read" {
  count = var.enable_security_services ? 1 : 0
  name  = "s3-bucket-public-read-prohibited"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}
resource "aws_config_config_rule" "root_mfa" {
  count = var.enable_security_services ? 1 : 0
  name  = "root-account-mfa-enabled"
  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}
resource "aws_config_config_rule" "restricted_ssh" {
  count = var.enable_security_services ? 1 : 0
  name  = "restricted-ssh"
  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_s3_bucket" "trail" {
  count         = var.enable_security_services ? 1 : 0
  bucket        = "${var.project_name}-trail-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "trail" {
  count                   = var.enable_security_services ? 1 : 0
  bucket                  = aws_s3_bucket.trail[0].id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  count  = var.enable_security_services ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "trail" {
  count  = var.enable_security_services ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "CloudTrailAclCheck", Effect = "Allow", Principal = { Service = "cloudtrail.amazonaws.com" }, Action = "s3:GetBucketAcl", Resource = aws_s3_bucket.trail[0].arn, Condition = { StringEquals = { "aws:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-trail" } } },
      { Sid = "CloudTrailWrite", Effect = "Allow", Principal = { Service = "cloudtrail.amazonaws.com" }, Action = "s3:PutObject", Resource = "${aws_s3_bucket.trail[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*", Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control", "aws:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-trail" } } }
    ]
  })
}
resource "aws_cloudtrail" "main" {
  count                         = var.enable_security_services ? 1 : 0
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.trail[0].bucket
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.trail]
}
resource "aws_securityhub_account" "main" {
  count                    = var.enable_security_services ? 1 : 0
  enable_default_standards = false
}
resource "aws_securityhub_standards_subscription" "fsbp" {
  count         = var.enable_security_services ? 1 : 0
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]
}
resource "aws_accessanalyzer_analyzer" "account" {
  count         = var.enable_security_services ? 1 : 0
  analyzer_name = "${var.project_name}-account-analyzer"
  type          = "ACCOUNT"
}
