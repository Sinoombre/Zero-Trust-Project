# Todos los buckets S3 del proyecto. Cada bucket sigue el mismo patrón:
# bucket, bloqueo de acceso público, cifrado, política, logging y ciclo de vida.
# Los controles a nivel de cuenta (aws_s3_account_public_access_block) están en hardening.tf.

# ---------------------------------------------------------------------------
# Bucket central de logs (ALB, VPC Flow Logs, S3 server access logs)
# ---------------------------------------------------------------------------
# Cuenta de ELB de la región: autoriza al ALB a escribir access logs.
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

# ---------------------------------------------------------------------------
# Bucket de AWS Config
# ---------------------------------------------------------------------------
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
      { Sid = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.config[0].arn, "${aws_s3_bucket.config[0].arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } },
      { Sid = "AWSConfigBucketPermissionsCheck", Effect = "Allow", Principal = { Service = "config.amazonaws.com" }, Action = ["s3:GetBucketAcl", "s3:ListBucket"], Resource = aws_s3_bucket.config[0].arn },
      { Sid = "AWSConfigBucketDelivery", Effect = "Allow", Principal = { Service = "config.amazonaws.com" }, Action = "s3:PutObject", Resource = "${aws_s3_bucket.config[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*", Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } } }
    ]
  })
}

resource "aws_s3_bucket_logging" "config" {
  count         = var.enable_security_services ? 1 : 0
  bucket        = aws_s3_bucket.config[0].id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access/config/"
  depends_on    = [aws_s3_bucket_policy.logs]
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

# ---------------------------------------------------------------------------
# Bucket de CloudTrail
# ---------------------------------------------------------------------------
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
      { Sid = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.trail[0].arn, "${aws_s3_bucket.trail[0].arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } },
      { Sid = "CloudTrailAclCheck", Effect = "Allow", Principal = { Service = "cloudtrail.amazonaws.com" }, Action = "s3:GetBucketAcl", Resource = aws_s3_bucket.trail[0].arn, Condition = { StringEquals = { "aws:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-trail" } } },
      { Sid = "CloudTrailWrite", Effect = "Allow", Principal = { Service = "cloudtrail.amazonaws.com" }, Action = "s3:PutObject", Resource = "${aws_s3_bucket.trail[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*", Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control", "aws:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-trail" } } }
    ]
  })
}

resource "aws_s3_bucket_logging" "trail" {
  count         = var.enable_security_services ? 1 : 0
  bucket        = aws_s3_bucket.trail[0].id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access/trail/"
  depends_on    = [aws_s3_bucket_policy.logs]
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