# CloudTrail (multi-region) con validación de integridad, cifrado KMS, SNS y CloudWatch Logs.
# El bucket de auditoría está en s3.tf. El topic SNS está en incident_response.tf.

resource "aws_kms_key" "cloudtrail" {
  count                   = var.enable_security_services ? 1 : 0
  description             = "KMS key for CloudTrail log encryption"
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
  tags = { Name = "${var.project_name}-cloudtrail-kms" }
}

resource "aws_kms_alias" "cloudtrail" {
  count         = var.enable_security_services ? 1 : 0
  name          = "alias/${var.project_name}-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail[0].id
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  count             = var.enable_security_services ? 1 : 0
  name              = "/aws/cloudtrail/${var.project_name}-trail"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.cloudtrail[0].id
  tags              = { Name = "${var.project_name}-cloudtrail-cw-log-group" }
}

resource "aws_iam_role" "cloudtrail" {
  count = var.enable_security_services ? 1 : 0
  name  = "${var.project_name}-cloudtrail-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "cloudtrail.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "cloudtrail" {
  count = var.enable_security_services ? 1 : 0
  name  = "cloudtrail-cloudwatch-logs"
  role  = aws_iam_role.cloudtrail[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = aws_cloudwatch_log_group.cloudtrail[0].arn
    }]
  })
}

resource "aws_cloudtrail" "main" {
  # checkov:skip=CKV_AWS_252:El SNS topic aws_sns_topic.security_alerts está definido en incident_response.tf y se referencia correctamente; checkov no resuelve referencias cruzadas entre archivos.
  count                         = var.enable_security_services ? 1 : 0
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.trail[0].bucket
  sns_topic_arn                 = aws_sns_topic.security_alerts.arn
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail[0].id
  cloud_watch_logs_group_arn    = aws_cloudwatch_log_group.cloudtrail[0].arn
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail[0].arn
  depends_on                    = [aws_s3_bucket_policy.trail]
}
