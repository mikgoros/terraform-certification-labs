output "instance_id" {
  value       = aws_instance.web.id
  description = "ID de la instancia EC2 creada"
}

output "public_ip" {
  value       = aws_instance.web.public_ip
  description = "IP pública de la instancia EC2 creada"
}

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "ID del VPC creado"
}

output "assets_bucket" {
  value = aws_s3_bucket.assets.bucket
}

output "environment_summary" {
  value = {
    environment    = var.environment
    region         = var.region
    instance_type  = var.instance_type
    is_production  = local.is_production
    root_volume_gb = local.root_volume_gb
  }

  description = "Resumen de la configuración efectiva (util para debugging)"
}

output "admin_token_echo" {
  value       = var.admin_token
  description = "Demuestra la propagacion de sensibilidad"
  sensitive   = true
}

output "web_url" {
  value       = "http://${aws_instance.web.public_ip}"
  description = "URL de acceso a la instancia"

  precondition {
    condition     = aws_instance.web.public_ip != ""
    error_message = "La instancia no tiene IP pública: revisa map_public_ip_on_launch."
  }
}
