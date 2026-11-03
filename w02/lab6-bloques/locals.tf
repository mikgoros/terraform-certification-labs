locals {
  name_prefix = "tf-assoc-l6-${var.environment}"
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Lesson      = "L6"
  }
}
