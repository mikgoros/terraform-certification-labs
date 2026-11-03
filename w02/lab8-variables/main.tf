data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpc"
    }
  )
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-public"
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
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  vpc_id      = aws_vpc.main.id
  name        = "${local.name_prefix}-web-sg"
  description = "tráfico HTTP de entrada"
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
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-web-sg"
    }
  )
}

resource "aws_instance" "web" {
  subnet_id              = aws_subnet.public.id
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web.id]
  monitoring             = local.monitoring
  root_block_device {
    volume_size = local.root_volume_gb
    volume_type = "gp3"
  }
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-web"
    }
  )
}

resource "aws_s3_bucket" "assets" {
  bucket = "${local.name_prefix}-assets-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}
