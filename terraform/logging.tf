# VPC Flow Logs hacia S3 y CloudWatch Logs.
# Los buckets están en s3.tf y el rol IAM en roles.tf.

# KMS key para cifrado de CloudWatch Log Groups (VPC Flow Logs)
resource "aws_kms_key" "cloudwatch_logs" {
  description             = "KMS key for CloudWatch Log Groups (VPC Flow Logs)"
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
      },
      {
        Sid    = "Allow CloudWatch Logs to use the key"
        Effect = "Allow"
        Principal = { Service = "logs.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  tags = { Name = "${var.project_name}-cw-logs-kms" }
}

resource "aws_kms_alias" "cloudwatch_logs" {
  name          = "alias/${var.project_name}-cw-logs"
  target_key_id = aws_kms_key.cloudwatch_logs.id
}

resource "aws_flow_log" "s3" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.logs.arn
  depends_on           = [aws_s3_bucket_policy.logs, aws_s3_bucket_public_access_block.logs]
}

resource "aws_cloudwatch_log_group" "flow" {
  name              = "/${var.project_name}/vpc-flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn
  depends_on        = [aws_kms_key.cloudwatch_logs]
}

resource "aws_flow_log" "cloudwatch" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn
}
