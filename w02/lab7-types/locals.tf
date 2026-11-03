locals {
  bucket_prefix = lower(var.project_name)

  primary_az = var.availability_zones[0]
  az_count   = length(var.availability_zones)
  azs_joined = join(",", var.availability_zones)

  first_type  = tolist(var.allowed_instance_types)[0]
  types_count = length(var.allowed_instance_types)

  cidr_east   = var.vpc_cidrs["us-east-1"]
  cidr_safe   = lookup(var.vpc_cidrs, "ap-south-1", "10.99.0.0/16")
  all_regions = keys(var.vpc_cidrs)
  all_cidrs   = values(var.vpc_cidrs)

  app_name     = var.app_config.name
  app_replicas = var.app_config.replicas
  app_type     = var.app_config["instance_type"]

  db_host = var.database_endpoint[0]
  db_port = var.database_endpoint[1]
  db_tls  = var.database_endpoint[2]
  db_url  = "postgres://${var.database_endpoint[0]}:${var.database_endpoint[1]}"

  open_ports = [for rule in var.ingress_rules : rule.port]

  az_set       = toset(var.availability_zones)
  types_list   = tolist(var.allowed_instance_types)
  port_as_text = tostring(var.database_endpoint[1])

  final_tags = merge(
    {
      Project   = var.project_name,
      ManagedBy = "terraform"
    },
    var.extra_tags
  )
}
