variable "vpc_cidr" {
  type        = string
  description = "CIDR base de la VPC"
  default     = "10.0.0.0/16"
}

variable "subnet_count" {
  type        = number
  description = "Numero de subnets publicas y privadas a crear"
  default     = 3
}

variable "environment" {
  type        = string
  description = "Entorno de trabajo"
  default     = "dev"
}
