output "vpc_id" {
  value = aws_vpc.main.id
}

output "web_instance_id" {
  value = aws_instance.web.id
}

output "web_instance_public_ip" {
  value = aws_instance.web.public_ip
}

output "assets_bucket_name" {
  value = aws_s3_bucket.assets.bucket
}
