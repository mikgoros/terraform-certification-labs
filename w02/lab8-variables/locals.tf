locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = merge(
    {
      Project     = var.project,
      Environment = var.environment,
      ManagedBy   = "terraform"
      Lesson      = "L8"
    },
    var.extra_tags
  )
  is_production      = var.environment == "prod"
  monitoring         = local.is_production
  root_volume_gb     = local.is_production ? 30 : 8
  public_subnet_cidr = cidrsubnet(var.vpc_cidr, 8, 0)
}
