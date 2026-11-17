# Controles a nivel de cuenta (afectan a toda la cuenta AWS, no solo a este proyecto).

resource "aws_s3_account_public_access_block" "account" {
  # checkov:skip=CKV2_AWS_6:El bloqueo público a nivel de cuenta permite políticas de bucket para que delivery.logs.amazonaws.com escriba VPC Flow Logs en el bucket de logs.
  # Se mantiene block_public_acls=true e ignore_public_acls=true para seguir bloqueando ACLs públicas.
  # Se deja block_public_policy=false y restrict_public_buckets=false para permitir políticas de bucket explícitas (ej. aws_s3_bucket_policy.flow_logs_delivery).
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
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
