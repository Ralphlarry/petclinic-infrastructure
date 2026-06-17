terraform {
  backend "s3" {
    bucket         = "petclinic-tf-state-524338476341"
    key            = "prod/networking.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "petclinic-tf-locks"
    encrypt        = true
  }
}