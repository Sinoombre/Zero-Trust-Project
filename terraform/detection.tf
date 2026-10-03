# Servicios detección: GuardDuty, Security Hub (FSBP) e IAM Access Analyzer.

# ---------------------------------------------------------------------------
# GuardDuty (con S3 Protection)
# ---------------------------------------------------------------------------
resource "aws_guardduty_detector" "main" {
  count                        = var.enable_security_services ? 1 : 0
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_guardduty_detector_feature" "s3_protection" {
  count       = var.enable_security_services ? 1 : 0
  detector_id = aws_guardduty_detector.main[0].id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

# ---------------------------------------------------------------------------
# Security Hub (con AWS Foundational Security Best Practices)
# ---------------------------------------------------------------------------
resource "aws_securityhub_account" "main" {
  count                    = var.enable_security_services ? 1 : 0
  enable_default_standards = false
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  count         = var.enable_security_services ? 1 : 0
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

resource "aws_accessanalyzer_analyzer" "account" {
  count         = var.enable_security_services ? 1 : 0
  analyzer_name = "${var.project_name}-account-analyzer"
  type          = "ACCOUNT"
}
