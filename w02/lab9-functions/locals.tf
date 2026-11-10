data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs             = slice(data.aws_availability_zones.available.names, 0, var.subnet_count)
  public_subnets  = [for i in range(var.subnet_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i in range(var.subnet_count) : cidrsubnet(var.vpc_cidr, 8, i + 100)]
  total_subnets   = length(local.public_subnets) + length(local.private_subnets)
  netmask         = cidrnetmask(var.vpc_cidr)
  is_production   = var.environment == "prod"
  name_prefix     = "tf-assoc-l9-${var.environment}"
  common_tags = merge(
    {
      Project     = "tf-assoc"
      Environment = var.environment
      ManagedBy   = "terraform"
      Lesson      = "L9"
    },
    local.is_production ? {
      Backup = "required"
      Tier   = "critical"
      } : {
      Backup = "none"
    }
  )
}
