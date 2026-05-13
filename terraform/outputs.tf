output "cloudfront_url" {
  description = "Public HTTPS URL for the game"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "api_url" {
  description = "Public API Gateway URL used by the frontend"
  value       = aws_apigatewayv2_api.game_api.api_endpoint
}

output "stats_table_name" {
  description = "DynamoDB table storing aggregate game statistics"
  value       = aws_dynamodb_table.game_stats.name
}

output "frontend_bucket_name" {
  description = "S3 bucket that stores the frontend files"
  value       = aws_s3_bucket.frontend.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID used for cache invalidations"
  value       = aws_cloudfront_distribution.frontend.id
}