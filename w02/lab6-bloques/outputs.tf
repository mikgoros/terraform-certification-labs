output "vpc_id" {
  value       = aws_vpc.main.id
  description = "ID de la VPC creada"
}

output "subnet_id" {
  value       = aws_subnet.public.id
  description = "ID de la subnet pública"
}

output "assets_bucket" {
  value       = aws_s3_bucket.assets.bucket
  description = "Nombre del bucket de assets"
}

output "region_in_use" {
  value       = data.aws_region.current.name
  description = "Región resuelta en tiempo de ejecución (data source)"
}

output "arn_preffix" {
  value       = "arn:${data.aws_partition.current.partition}:s3:::"
  description = "Prefijo ARN de la partición AWS actual (aws, aws-cn, aws-us-gov)"
}
