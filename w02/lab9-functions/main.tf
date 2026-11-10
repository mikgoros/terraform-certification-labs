data "aws_caller_identity" "current" {}
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}
data "aws_region" "current" {}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpc"
    }
  )
}

resource "aws_subnet" "public" {
  count  = length(local.public_subnets)
  vpc_id = aws_vpc.main.id

  cidr_block              = local.public_subnets[count.index]
  availability_zone       = element(local.azs, count.index)
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name = format("%s-public-%02d", local.name_prefix, count.index + 1)
      Tier = "public"
      AZ   = element(local.azs, count.index)
    }
  )
}

resource "aws_subnet" "private" {
  count  = length(local.private_subnets)
  vpc_id = aws_vpc.main.id

  cidr_block        = local.private_subnets[count.index]
  availability_zone = element(local.azs, count.index)
  tags = merge(
    local.common_tags,
    {
      Name = format("%s-private-%02d", local.name_prefix, count.index + 1)
      Tier = "private"
    }
  )
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-igw"
    }
  )
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-rt-public"
    }
  )
}

resource "aws_route_table_association" "public" {
  count          = length(local.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  vpc_id      = aws_vpc.main.id
  name        = "${local.name_prefix}-web-sg"
  description = "HTTP publico"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_s3_bucket" "assets" {
  bucket = "${local.name_prefix}-assets-${data.aws_caller_identity.current.account_id}"

  tags = local.common_tags
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "good" {
  bucket = "tf-assoc-l9-good-${random_id.suffix.hex}"
}

resource "aws_s3_object" "site" {
  for_each     = fileset("${path.module}/site", "**/*.html")
  bucket       = aws_s3_bucket.assets.id
  key          = "site/${each.value}"
  source       = "${path.module}/site/${each.value}"
  etag         = filemd5("${path.module}/site/${each.value}")
  content_type = "text/html"
}

resource "aws_instance" "web" {
  subnet_id              = aws_subnet.public[0].id
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = templatefile(
    "${path.module}/templates/bootstrap.sh.tftpl",
    {
      region            = data.aws_region.current.name,
      bucket_name       = aws_s3_bucket.assets.bucket,
      environment       = var.environment,
      packages          = ["nginx", "jq"],
      enable_monitoring = local.is_production
    }
  )

  user_data_replace_on_change = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-web"
    }
  )
}
