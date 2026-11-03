variable "region" {
  type        = string
  default     = "us-east-1"
  description = "Región de AWS donde se realiza el desplliegue"
}

variable "environment" {
  type        = string
  nullable    = false
  description = "Entorno lógico: dev | staging | prod (obligatorio, sin default)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser dev, staging o prod."
  }
}

variable "project" {
  type        = string
  default     = "tf-assoc"
  description = "Prefijo de nombres de recursos"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Tipo de instancia EC2"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR de la VPC"
}

variable "extra_tags" {
  type        = map(string)
  default     = {}
  description = "Tags adicionales a fusionar con los comunes"
}

variable "admin_token" {
  type        = string
  default     = "cambiame"
  description = "Token de ejemplo para demostrar el comportamiento de sensitive"
  sensitive   = true
}
