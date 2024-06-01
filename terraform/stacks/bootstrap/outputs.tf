output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "table_arn" {
  value = aws_dynamodb_table.this.arn
}
