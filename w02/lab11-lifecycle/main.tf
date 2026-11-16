data "aws_caller_identity" "current" {}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

data "aws_instances" "app" {
  instance_tags = { Name = "tf-assoc-l11-drift" }

  # The tag filter is a string, not a reference; wait for the instance.
  depends_on = [aws_instance.drift]
}

variable "app_version" {
  type    = string
  default = "1.0.0"
}

# ─────────────────────────────────────────────
# Red base
# ─────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = { Name = "tf-assoc-l11-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = { Name = "tf-assoc-l11-public" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "tf-assoc-l11-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "tf-assoc-l11-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────────
# prevent_destroy: bucket protegido
# ─────────────────────────────────────────────

resource "aws_s3_bucket" "protegido" {
  bucket = "tf-assoc-l11-protegido-${data.aws_caller_identity.current.account_id}"

  # Set to true to reproduce the guard; false keeps the lab destroyable.
  lifecycle {
    prevent_destroy = false
  }
}

# ─────────────────────────────────────────────
# create_before_destroy: SG con name_prefix
# ─────────────────────────────────────────────

resource "aws_security_group" "demo" {
  name_prefix = "tf-assoc-l11-demo-"
  description = "SG para probar create_before_destroy"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "tf-assoc-l11-demo-sg"
  }

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

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────
# ignore_changes: EC2 con tag externo
# ─────────────────────────────────────────────

resource "aws_instance" "drift" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public.id

  tags = {
    Name        = "tf-assoc-l11-drift"
    Environment = "dev"
  }

  lifecycle {
    ignore_changes = [tags["PatchGroup"]]
  }
}

# ─────────────────────────────────────────────
# replace_triggered_by: botón de redeploy
# ─────────────────────────────────────────────

resource "terraform_data" "deploy_marker" {
  input = var.app_version
}

resource "aws_instance" "versioned" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public.id

  tags = { Name = "tf-assoc-l11-versioned" }

  lifecycle {
    replace_triggered_by = [terraform_data.deploy_marker]
  }
}

output "protegido_bucket" {
  value = aws_s3_bucket.protegido.bucket
}

output "drift_ip" {
  value = aws_instance.drift.public_ip
}

output "versioned_ip" {
  value = aws_instance.versioned.public_ip
}

output "drift_ids" {
  value = data.aws_instances.app.ids
}
