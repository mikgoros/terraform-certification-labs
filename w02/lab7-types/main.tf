resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidrs["us-east-1"]
  enable_dns_hostnames = var.enable_dns
  tags                 = local.final_tags
}

resource "aws_subnet" "by_count" {
  count             = var.subnet_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags              = merge(local.final_tags, { Name = "subnet-${count.index}" })
}

resource "aws_s3_bucket" "by_region" {
  for_each = var.vpc_cidrs
  bucket   = "${local.bucket_prefix}-${each.key}-${data.aws_caller_identity.current.account_id}"
  tags     = merge(local.final_tags, { Region = each.key, Cidr = each.value })
}

resource "aws_ssm_parameter" "az_marker" {
  for_each = toset(var.availability_zones)
  name     = "/${var.project_name}/az/${each.key}"
  type     = "String"
  value    = each.value
}

data "aws_caller_identity" "current" {}
