resource "aws_key_pair" "accenture_demo" {
  key_name   = "accenture_demo_key"
  public_key = file(pathexpand(var.ssh_accenture_demo_public_key))
}