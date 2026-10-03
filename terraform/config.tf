# AWS Config: recorder, delivery channel y reglas managed.
# El bucket está en s3.tf y el rol IAM en roles.tf.

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

# Reglas de AWS Config para reforzar la seguridad de la cuenta.
resource "aws_config_config_rule" "ec2_in_vpc" {
  count = var.enable_security_services ? 1 : 0
  name  = "ec2-instances-in-vpc"
  source {
    owner             = "AWS"
    source_identifier = "INSTANCES_IN_VPC"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
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
