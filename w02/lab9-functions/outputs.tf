output "network_plan" {
  value = {
    vpc_cidr        = var.vpc_cidr
    netmask         = local.netmask
    public_cidrs    = local.public_subnets
    private_cidrs   = local.private_subnets
    total_subnets   = local.total_subnets
    azs_usadas      = local.azs
    primer_host_dns = cidrhost(local.public_subnets[0], 2)
  }
  description = "Resumen del direccionamiento calculado"
}

output "web_public_ip" {
  value       = aws_instance.web.public_ip
  description = "IP publica de la web levantada"
}

output "assets_bucket" {
  value = aws_s3_bucket.assets.bucket
}
