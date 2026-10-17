resource "aws_key_pair" "switchyard_llm_routing_aws" {
  key_name   = "switchyard-llm-routing-aws"
  public_key = file(pathexpand(var.ssh_switchyard_llm_routing_aws_public_key))
}
