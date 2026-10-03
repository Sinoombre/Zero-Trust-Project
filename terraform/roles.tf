# Roles IAM
#   - EC2 + SSM (aws_iam_role.ec2_ssm + instance profile)
#   - AWS Config (aws_iam_role.config)
#   - VPC Flow Logs (aws_iam_role.flow_logs)
#   - GuardDuty, Security Hub, Access Analyzer usan roles service-linked que AWS crea solo.
#   - Lambda Responder (respuesta automática a incidentes).

# Variables locales
locals {
  responder_function_name = "${var.project_name}-responder"
  responder_log_group_arn = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.responder_function_name}"
  alerts_topic_arn        = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.project_name}-security-alerts"
  ec2_arn_prefix          = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
}

# ---------------------------------------------------------------------------
# EC2 + Session Manager
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-instance-profile-${random_id.suffix.hex}"
  role = aws_iam_role.ec2_ssm.name
}

# ---------------------------------------------------------------------------
# AWS Config
# ---------------------------------------------------------------------------
resource "aws_iam_role" "config" {
  count = var.enable_security_services ? 1 : 0
  name  = "${var.project_name}-config-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "config.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  count      = var.enable_security_services ? 1 : 0
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# ---------------------------------------------------------------------------
# VPC Flow Logs -> CloudWatch Logs
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# AWS Lambda
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_responder" {
  name        = "${var.project_name}-lambda-responder-role-${random_id.suffix.hex}"
  description = "Ejecuta la Lambda que aísla instancias comprometidas y notifica por SNS."
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_responder" {
  name = "isolate-instance-and-notify"
  role = aws_iam_role.lambda_responder.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [local.responder_log_group_arn, "${local.responder_log_group_arn}:*"]
      },
      {
        # Las acciones "Describe*" no admiten restricción por recurso.
        Sid      = "ReadEc2State"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeSecurityGroups"]
        Resource = "*"
      },
      {
        # Reemplazar los SG de la instancia por el SG de cuarentena (vacío).
        Sid      = "IsolateInstance"
        Effect   = "Allow"
        Action   = "ec2:ModifyInstanceAttribute"
        Resource = ["${local.ec2_arn_prefix}:instance/*", "${local.ec2_arn_prefix}:security-group/*"]
      },
      {
        Sid      = "PublishAlert"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = local.alerts_topic_arn
      }
    ]
  })
}