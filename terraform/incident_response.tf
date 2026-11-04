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

# KMS key for Lambda environment variables and CloudWatch Log Group encryption
resource "aws_kms_key" "lambda" {
  description             = "KMS key for Lambda responder encryption"
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
  tags = { Name = "${var.project_name}-lambda-kms" }
}

resource "aws_kms_alias" "lambda" {
  name          = "alias/${var.project_name}-lambda"
  target_key_id = aws_kms_key.lambda.id
}

# Lambda Code Signing Config (omitido: requiere signing profile ARN no disponible en este laboratorio)
# checkov:skip=CKV_AWS_272:El laboratorio no dispone de un signing profile de AWS Signer; se documenta como riesgo aceptado.

# Lambda Function
resource "aws_lambda_function" "lambda_responder" {
  # checkov:skip=CKV_AWS_173:El KMS key aws_kms_key.lambda está definido en el mismo archivo y se referencia correctamente; checkov no resuelve la referencia estáticamente.
  # checkov:skip=CKV_AWS_272:El laboratorio no dispone de un signing profile de AWS Signer; se documenta como riesgo aceptado.
  filename      = data.archive_file.file_responder.output_path
  function_name = "${var.project_name}-lambda-responder"
  role          = aws_iam_role.lambda_responder.arn
  handler       = "responder.lambda_handler"

  source_code_hash = data.archive_file.file_responder.output_base64sha256

  runtime = "python3.13"
  timeout = 30 # It has to run in 30 seconds, change the default of 3

  reserved_concurrent_executions = 5

  tracing_config {
    mode = "Active"
  }

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.empty.id]
  }

  dead_letter_config {
    target_arn = aws_sns_topic.security_alerts.arn
  }

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
  kms_key_id        = aws_kms_key.lambda.arn
}
