output "bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.tfstate.arn
}
