resource "aws_security_group" "allow_gateway_nodes" {
  name        = "allow_gateway_nodes"
  description = "Allow Access to Gateway Nodes"
  vpc_id      = data.aws_vpc.current.id

  tags = {
    Name = "allow_gateway_nodes"
  }
}

resource "aws_security_group" "allow_model_nodes" {
  name        = "allow_model_nodes"
  description = "Allow Access to Model Instances"
  vpc_id      = data.aws_vpc.current.id

  tags = {
    Name = "allow_model_nodes"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_gateway_ports" {
  security_group_id = aws_security_group.allow_gateway_nodes.id
  for_each          = toset(local.gateway_ports)
  cidr_ipv4         = local.cidr_ipv4
  from_port         = each.value
  ip_protocol       = "tcp"
  to_port           = each.value
}

resource "aws_vpc_security_group_ingress_rule" "allow_model_nodes_ssh" {
  security_group_id = aws_security_group.allow_model_nodes.id
  for_each          = toset(local.model_ports)
  cidr_ipv4         = local.cidr_ipv4
  from_port         = each.value
  ip_protocol       = "tcp"
  to_port           = each.value
}

resource "aws_vpc_security_group_ingress_rule" "allow_model_nodes_sg" {
  security_group_id            = aws_security_group.allow_model_nodes.id
  for_each                     = toset(local.model_sg_ports)
  referenced_security_group_id = aws_security_group.allow_gateway_nodes.id
  from_port                    = each.value
  ip_protocol                  = "tcp"
  to_port                      = each.value
}