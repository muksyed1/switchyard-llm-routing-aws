data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_vpc" "current" {
  default = true
}

data "aws_ami" "ubuntu_latest" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}