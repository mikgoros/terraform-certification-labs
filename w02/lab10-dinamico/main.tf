terraform {
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "subnets" {
  type = map(object({
    cidr   = string
    az_idx = number
  }))

  default = {
    "web-a" = { cidr = "10.0.11.0/24", az_idx = 0 }
    "web-b" = { cidr = "10.0.12.0/24", az_idx = 1 }
    "web-c" = { cidr = "10.0.13.0/24", az_idx = 3 }
  }
}

variable "ingress_rules" {
  type = list(object({
    description = string
    port        = number
    cidr_blocks = list(string)
  }))

  default = [
    { description = "HTTP", port = 80, cidr_blocks = ["0.0.0.0/0"] },
    { description = "HTTPS", port = 443, cidr_blocks = ["0.0.0.0/0"] },
    { description = "HTTP", port = 8080, cidr_blocks = ["0.0.0.0/0"] },
  ]
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "lab10-vpc"
  }
}

resource "aws_subnet" "con_each" {
  for_each          = var.subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = data.aws_availability_zones.available.names[each.value.az_idx]

  tags = {
    Name = "lab10-foreach-${each.key}"
  }
}

resource "aws_ssm_parameter" "marker" {
  for_each = toset(var.subnet_cidrs)
  name     = "/lab10/${replace(each.key, "/", "-")}"
  type     = "String"
  value    = each.key
}

resource "aws_security_group" "dinamico" {
  name        = "lab10-dynamic-sg"
  description = "SG with dynamic rules"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.ingress_rules
    iterator = regla

    content {
      description = regla.value.description
      from_port   = regla.value.port
      to_port     = regla.value.port
      protocol    = "tcp"
      cidr_blocks = regla.value.cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "subnet_ids_foreach" {
  value = { for k, s in aws_subnet.con_each : k => s.id }
}

output "subnet_ids_lista" {
  value = values(aws_subnet.con_each)[*].id
}


