variable "project_name" {
  type        = string
  default     = "tf-assoc-l7"
  description = "Prefijo de nombres"
}

variable "subnet_count" {
  type        = number
  default     = 3
  description = "Número de subnets (Terraform no distingue int de float: todo es number)"
}

variable "enable_dns" {
  type        = bool
  default     = true
  description = "Habilitar soporte DNS en la VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  description = "AZs en orden de preferencia"
}

variable "allowed_instance_types" {
  type        = set(string)
  default     = ["t3.micro", "t3.small", "t3.medium"]
  description = "Tipos de instancia permitidos"
}

variable "vpc_cidrs" {
  type        = map(string)
  default     = { "us-east-1" = "10.0.0.0/16", "us-east-2" = "10.1.0.0/16", "eu-west-1" = "10.2.0.0/16" }
  description = "CIDR de VPC por región"
}

variable "app_config" {
  type = object({
    name          = string
    instance_type = optional(string, "t3.micro")
    replicas      = optional(number, 2)
    monitoring    = optional(bool, false)
    tags          = optional(map(string), {})
  })
  default     = { name = "api" }
  description = "Configuración de la aplicación (object con atributos opcionales)"
}

variable "database_endpoint" {
  type        = tuple([string, number, bool])
  default     = ["db.internal", 5432, true]
  description = "Endpoint de base de datos como tupla heterogenea"
}

variable "ingress_rules" {
  type = list(object({
    description = string
    port        = number
    protocol    = optional(string, "tcp")
    cidr_blocks = list(string)
  }))
  default = [{
    description = "HTTP publico"
    port        = 80
    cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "HTTPS publico"
      port        = 443
      cidr_blocks = ["0.0.0.0/0"]
  }]
}

variable "extra_tags" {
  type        = map(string)
  default     = {}
  description = "Tags adicionales"
}

variable "kms_key_id" {
  type     = string
  default  = null
  nullable = true
}

variable "wildcard" {
  default     = { cualquier = "cosa" }
  description = "Acepta cualquier tipo"
}
