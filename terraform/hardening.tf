resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}


resource "aws_config_config_rule" "ec2_in_vpc" {
  count = var.enable_security_services ? 1 : 0
  name  = "ec2-instances-in-vpc"
  source {
    owner             = "AWS"
    source_identifier = "INSTANCES_IN_VPC"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}


data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket" "logs" {
  bucket        = "${var.project_name}-logs-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } },
      { Sid = "AlbAccessLogs", Effect = "Allow", Principal = { AWS = data.aws_elb_service_account.main.arn }, Action = "s3:PutObject", Resource = "${aws_s3_bucket.logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*" },
      { Sid = "FlowLogsAclCheck", Effect = "Allow", Principal = { Service = "delivery.logs.amazonaws.com" }, Action = "s3:GetBucketAcl", Resource = aws_s3_bucket.logs.arn },
      { Sid = "FlowLogsWrite", Effect = "Allow", Principal = { Service = "delivery.logs.amazonaws.com" }, Action = "s3:PutObject", Resource = "${aws_s3_bucket.logs.arn}/flow-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*", Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control", "aws:SourceAccount" = data.aws_caller_identity.current.account_id } } },
      { Sid = "S3ServerAccessLogs", Effect = "Allow", Principal = { Service = "logging.s3.amazonaws.com" }, Action = "s3:PutObject", Resource = "${aws_s3_bucket.logs.arn}/s3-access/*", Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } } }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.logs]
}

resource "aws_s3_bucket_logging" "logs" {
  bucket        = aws_s3_bucket.logs.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access/logs/"
  depends_on    = [aws_s3_bucket_policy.logs]
}
resource "aws_s3_bucket_logging" "trail" {
  count         = var.enable_security_services ? 1 : 0
  bucket        = aws_s3_bucket.trail[0].id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access/trail/"
  depends_on    = [aws_s3_bucket_policy.logs]
}
resource "aws_s3_bucket_logging" "config" {
  count         = var.enable_security_services ? 1 : 0
  bucket        = aws_s3_bucket.config[0].id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access/config/"
  depends_on    = [aws_s3_bucket_policy.logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "expire-and-cleanup"
    status = "Enabled"
    filter {}
    expiration { days = 365 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  count  = var.enable_security_services ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  rule {
    id     = "expire-and-cleanup"
    status = "Enabled"
    filter {}
    expiration { days = 365 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "config" {
  count  = var.enable_security_services ? 1 : 0
  bucket = aws_s3_bucket.config[0].id
  rule {
    id     = "expire-and-cleanup"
    status = "Enabled"
    filter {}
    expiration { days = 365 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_account_public_access_block" "account" {
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_flow_log" "s3" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = "${aws_s3_bucket.logs.arn}/flow-logs/"
  depends_on           = [aws_s3_bucket_policy.logs]
}

resource "aws_cloudwatch_log_group" "flow" {
  name              = "/${var.project_name}/vpc-flow-logs"
  retention_in_days = 365
}
resource "aws_iam_role" "flow_logs" {
  name = "${var.project_name}-flowlogs-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "vpc-flow-logs.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy" "flow_logs" {
  name = "write-flow-logs"
  role = aws_iam_role.flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"], Resource = "${aws_cloudwatch_log_group.flow.arn}:*" },
      { Effect = "Allow", Action = "logs:DescribeLogGroups", Resource = "*" }
    ]
  })
}
resource "aws_flow_log" "cloudwatch" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn
}


resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-default-sg-locked" }
}


resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}
resource "aws_ebs_snapshot_block_public_access" "this" {
  state = "block-all-sharing"
}


resource "aws_ssm_service_setting" "block_public_documents" {
  setting_id    = "/ssm/documents/console/public-sharing-permission"
  setting_value = "Disable"
}


resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
}

resource "aws_vpc_endpoint" "ec2" {
  count               = var.enable_ssm_interface_endpoints && var.enable_ec2_interface_endpoint ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.ssm_endpoints[0].id]
  private_dns_enabled = true
  tags                = { Name = "${var.project_name}-ec2-endpoint" }
}
