resource "aws_dynamodb_table" "terraform_lock" {
  name         = "petclinic-tf-locks"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project     = "petclinic"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}