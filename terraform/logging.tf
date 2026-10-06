# VPC Flow Logs hacia S3 y CloudWatch Logs. 
# Los buckets están en s3.tf y el rol IAM en roles.tf.

resource "aws_flow_log" "s3" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = "${aws_s3_bucket.logs.arn}/flow-logs/"
  depends_on           = [aws_s3_bucket_policy.logs]
}

resource "aws_cloudwatch_log_group" "flow" {
  name              = "/${var.project_name}/vpc-flow-logs"
  retention_in_days = 365
}

resource "aws_flow_log" "cloudwatch" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn
}