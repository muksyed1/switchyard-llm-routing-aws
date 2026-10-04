variable "region" {
  default     = "us-west-2"
  description = "AWS Region"
  type        = string
}

variable "ssh_accenture_demo_public_key" {
  type        = string
  default     = "~/.ssh/accenture_demo.pub"
  description = "The OpenSSH public key string used for Accenture Demo."
}

variable "egress_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Egress Allow All Networks"
}

