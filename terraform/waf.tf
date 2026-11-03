# WAFv2 regional asociado al ALB: reglas OWASP gestionadas, rate limit, log4j y logging.

resource "aws_wafv2_web_acl" "alb" {
  name        = "${var.project_name}-web-acl"
  description = "Managed OWASP protections, rate limit, Log4j protection and logging for the demo ALB."
  scope       = "REGIONAL"
  default_action {
    allow {}
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-web-acl"
    sampled_requests_enabled   = true
  }
  rule {
    name     = "AWSManagedCommonRuleSet"
    priority = 10
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common-rules"
      sampled_requests_enabled   = true
    }
  }
  rule {
    name     = "AWSManagedSQLiRuleSet"
    priority = 20
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "sqli-rules"
      sampled_requests_enabled   = true
    }
  }
  rule {
    name     = "AWSManagedKnownBadInputsRuleSet"
    priority = 25
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }
  rule {
    name     = "AWSManagedAmazonIpReputationList"
    priority = 26
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ip-reputation"
      sampled_requests_enabled   = true
    }
  }
  rule {
    name     = "RateLimit"
    priority = 30
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }
}

# WAFv2 Logging Configuration hacia el bucket de logs S3
resource "aws_wafv2_web_acl_logging_configuration" "alb" {
  web_acl_arn             = aws_wafv2_web_acl.alb.arn
  log_destination_configs = [aws_s3_bucket.logs.arn]
  redacted_fields {
    single_header { name = "Authorization" }
    single_header { name = "Cookie" }
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
}
