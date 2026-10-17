variable "region" {
  default     = "us-west-2"
  description = "AWS Region"
  type        = string
}

variable "ssh_switchyard_llm_routing_aws_public_key" {
  type        = string
  default     = "~/.ssh/switchyard_llm_routing_aws.pub"
  description = "The OpenSSH public key string used for Switchyard LLM Routing AWS Demo."
}

variable "egress_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Egress Allow All Networks"
}

