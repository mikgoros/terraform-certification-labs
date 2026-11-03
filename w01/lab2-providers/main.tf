resource "random_pet" "bucket_suffix" {
  length = 2
}

resource "aws_s3_bucket" "home" {
  bucket = "lab2-home-${random_pet.bucket_suffix.id}"
  tags   = { Environment = "dev", Region = "eu-west-1" }
}

resource "aws_s3_bucket" "replica" {
  provider = aws.useast
  bucket   = "lab2-replica-${random_pet.bucket_suffix.id}"
  tags     = { Environment = "dev", Region = "us-east-1" }
}
