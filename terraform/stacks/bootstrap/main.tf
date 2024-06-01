resource "aws_s3_bucket" "this" {
  bucket = "ehakan-homelab-tf-state"
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "this" {
  name         = "ehakan-homelab-tf-state-lock"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}
