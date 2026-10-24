# Mensajes SNS
resource "aws_sns_topic" "security_alerts" {
  name              = "${var.project_name}-security-alerts"
  kms_master_key_id = "alias/aws/sns" # Habilita el cifrado en reposo
}

resource "aws_sns_topic_subscription" "email_messages" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}