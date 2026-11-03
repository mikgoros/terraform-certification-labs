output "suffix" {
  value = random_pet.bucket_suffix.id
}

output "home_bucket" {
  value = aws_s3_bucket.home.bucket
}

output "replica_bucket" {
  value = aws_s3_bucket.replica.bucket
}
