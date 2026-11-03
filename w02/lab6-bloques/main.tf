resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-subnet-public" })
}

resource "aws_s3_bucket" "assets" {
  bucket = "${local.name_prefix}-assets-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}
