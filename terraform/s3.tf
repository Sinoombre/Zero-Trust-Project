# Todos los buckets S3 del proyecto. Cada bucket sigue el mismo patrón:
# bucket, bloqueo de acceso público, cifrado KMS, versioning, replicación, notificaciones,
# política, logging y ciclo de vida.
# Los controles a nivel de cuenta (aws_s3_account_public_access_block) están en hardening.tf.

# KMS key para cifrado de buckets S3
resource "aws_kms_key" "s3_buckets" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "key-default-1"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
  tags = { Name = "${var.project_name}-s3-kms" }
}

resource "aws_kms_alias" "s3_buckets" {
  name          = "alias/${var.project_name}-s3"
  target_key_id = aws_kms_key.s3_buckets.id
}

# IAM role para replicación entre buckets S3
resource "aws_iam_role" "s3_replication" {
  name = "${var.project_name}-s3-replication-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "s3-replication-policy"
  role = aws_iam_role.s3_replication.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = [aws_s3_bucket.logs.arn, aws_s3_bucket.replication_destination.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectRetention",
          "s3:GetObjectLegalHold"
        ]
        Resource = "${aws_s3_bucket.logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:ObjectOwnerOverrideToBucketOwner"
        ]
        Resource = "${aws_s3_bucket.replication_destination.arn}/*"
      }
    ]
  })
}

# Bucket destino para replicación entre regiones
resource "aws_s3_bucket" "replication_destination" {
  bucket        = "${var.project_name}-replication-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"
  force_destroy = false
  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "replication_destination" {
  bucket                  = aws_s3_bucket.replication_destination.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "replication_destination" {
  bucket = aws_s3_bucket.replication_destination.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_buckets.id
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "replication_destination" {
  bucket        = aws_s3_bucket.replication_destination.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access/replication-destination/"
  depends_on    = [aws_s3_bucket_policy.logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "replication_destination" {
  bucket = aws_s3_bucket.replication_destination.id
  rule {
    id     = "expire-and-cleanup"
    status = "Enabled"
    filter {}
    expiration { days = 365 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_notification" "replication_destination" {
  bucket = aws_s3_bucket.replication_destination.id
  topic {
    topic_arn = aws_sns_topic.security_alerts.arn
    events    = ["s3:ReducedRedundancyLostObject", "s3:ObjectCreation:*"]
  }
}

# ---------------------------------------------------------------------------
# Bucket central de logs (ALB, VPC Flow Logs, S3 server access logs)
# ---------------------------------------------------------------------------
# Cuenta de ELB de la región: autoriza al ALB a escribir access logs.
data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket" "logs" {
  bucket        = "${var.project_name}-logs-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"
  force_destroy = false
  versioning {
    enabled = true
  }
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
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_buckets.id
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_replication_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  role   = aws_iam_role.s3_replication.arn
  rule {
    id     = "replicate-all"
    status = "Enabled"
    destination {
      bucket        = aws_s3_bucket.replication_destination.arn
      storage_class = "STANDARD"
    }
    delete_marker_replication {
      status = "Disabled"
    }
  }
}

resource "aws_s3_bucket_notification" "logs" {
  bucket = aws_s3_bucket.logs.id
  topic {
    topic_arn     = aws_sns_topic.security_alerts.arn
    events        = ["s3:ReducedRedundancyLostObject", "s3:ObjectCreation:*"]
    filter_prefix = "alb/"
    filter_suffix = ".log"
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
  versioning {
    enabled = true
  }
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
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_buckets.id
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_replication_configuration" "config" {
  count  = var.enable_security_services ? 1 : 0
  bucket = aws_s3_bucket.config[0].id
  role   = aws_iam_role.s3_replication.arn
  rule {
    id     = "replicate-all"
    status = "Enabled"
    destination {
      bucket        = aws_s3_bucket.replication_destination.arn
      storage_class = "STANDARD"
    }
    delete_marker_replication {
      status = "Disabled"
    }
  }
}

resource "aws_s3_bucket_notification" "config" {
  count  = var.enable_security_services ? 1 : 0
  bucket = aws_s3_bucket.config[0].id
  topic {
    topic_arn = aws_sns_topic.security_alerts.arn
    events    = ["s3:ReducedRedundancyLostObject", "s3:ObjectCreation:*"]
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
  versioning {
    enabled = true
  }
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
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_buckets.id
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_replication_configuration" "trail" {
  count  = var.enable_security_services ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  role   = aws_iam_role.s3_replication.arn
  rule {
    id     = "replicate-all"
    status = "Enabled"
    destination {
      bucket        = aws_s3_bucket.replication_destination.arn
      storage_class = "STANDARD"
    }
    delete_marker_replication {
      status = "Disabled"
    }
  }
}

resource "aws_s3_bucket_notification" "trail" {
  count  = var.enable_security_services ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  topic {
    topic_arn = aws_sns_topic.security_alerts.arn
    events    = ["s3:ReducedRedundancyLostObject", "s3:ObjectCreation:*"]
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
