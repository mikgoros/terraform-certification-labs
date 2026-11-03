variable "region" {
  type        = string
  description = "Región de AWSdonde desplegar el lab"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Entorno lógico (dev, staging, prod)"
  default     = "dev"
}
