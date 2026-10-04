
resource "aws_security_group" "allow_egress_all" {
  name        = "allow_egress_all"
  description = "Allow Egress Access to All Instances"
  vpc_id      = data.aws_vpc.current.id

  tags = {
    Name = "allow_egress_all"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_all_sg" {
  security_group_id = aws_security_group.allow_egress_all.id
  cidr_ipv4         = var.egress_cidr
  ip_protocol       = "-1"
}