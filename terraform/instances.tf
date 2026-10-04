resource "aws_instance" "demo_gateway" {
  ami                    = data.aws_ami.ubuntu_latest.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.accenture_demo.key_name
  vpc_security_group_ids = [aws_security_group.allow_egress_all.id, aws_security_group.allow_gateway_nodes.id]
  tags = {
    Name = "demo-gateway"
  }
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
}

resource "aws_instance" "demo_model" {
  ami                    = data.aws_ami.ubuntu_latest.id
  instance_type          = "m7i-flex.large"
  for_each               = local.demo_models
  key_name               = aws_key_pair.accenture_demo.key_name
  vpc_security_group_ids = [aws_security_group.allow_egress_all.id, aws_security_group.allow_model_nodes.id]
  tags = {
    Name  = each.key
    Model = each.value
  }
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }
}