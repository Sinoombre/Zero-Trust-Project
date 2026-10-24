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

data "archive_file" "file_responder" {
  type        = "zip"
  source_file = "${path.module}/lambda/responder.py"
  output_path = "${path.module}/lambda/responder.zip"
}

# Lambda Function
resource "aws_lambda_function" "lambda_responder" {
  filename      = data.archive_file.file_responder.output_path
  function_name = "${var.project_name}-lambda-responder"
  role          = aws_iam_role.lambda_responder.arn
  handler       = "responder.lambda_handler"

  source_code_hash = data.archive_file.file_responder.output_base64sha256

  runtime = "python3.13"
  timeout = 30 # It has to run in 30 seconds, change the default of 3

  environment {
    variables = {
      EMPTY_SG_ID   = aws_security_group.empty.id
      SNS_TOPIC_ARN = aws_sns_topic.security_alerts.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.log_responder]
}

resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "${var.project_name}-guardduty-high-severity"
  description = "Capturar severidad HIGH o superior (>=7); activa Lambda Responder"

  event_pattern = jsonencode({
    "source" : ["aws.guardduty"],
    "detail-type" : ["GuardDuty Finding"],
    "detail" : {
      "severity" : [{ "numeric" : [">=", 7] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "responder" {
  rule = aws_cloudwatch_event_rule.guardduty_high.name
  arn  = aws_lambda_function.lambda_responder.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_responder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_high.arn
}

resource "aws_cloudwatch_log_group" "log_responder" {
  name              = "/aws/lambda/${var.project_name}-lambda-responder"
  retention_in_days = 365
}
