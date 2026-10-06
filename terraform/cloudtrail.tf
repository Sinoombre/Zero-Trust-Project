# CloudTrail (single-region) con validación de integridad.
# El bucket de auditoría está en s3.tf.

resource "aws_cloudtrail" "main" {
  count                         = var.enable_security_services ? 1 : 0
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.trail[0].bucket
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.trail]
}