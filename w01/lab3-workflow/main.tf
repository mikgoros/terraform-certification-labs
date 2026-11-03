resource "random_pet" "suffix" {
  length = 2
}

resource "aws_s3_bucket" "primary" {
  bucket = "lab3-demo-${random_pet.suffix.id}"
  tags = {
    "Environment" = "dev"
    "ManagedBy"   = "terraform"
  }
}

resource "aws_s3_bucket" "extras" {
  count  = 1
  bucket = "lab3-extra-${count.index}-${random_pet.suffix.id}"
}
