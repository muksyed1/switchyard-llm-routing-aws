output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  value = data.aws_caller_identity.current.arn
}

output "caller_user" {
  value = data.aws_caller_identity.current.user_id
}

output "region" {
  value = data.aws_region.current.region
}

output "vpc" {
  value = data.aws_vpc.current.id
}

output "ami" {
  value = data.aws_ami.ubuntu_latest.id
}

output "gateway_public_ip" {
  value = aws_instance.demo_gateway.public_ip
}

output "grafana_url" {
  value = "http://${aws_instance.demo_gateway.public_ip}:3000"
}

output "switchyard_url" {
  value = "http://${aws_instance.demo_gateway.public_ip}:4000"
}

output "prometheus_url" {
  value = "http://${aws_instance.demo_gateway.public_ip}:9090"
}

output "demo_model_public_ips" {
  description = "A map of demo model instances to their public IP addresses"
  value       = { for name, inst in aws_instance.demo_model : name => inst.public_ip }
}

output "demo_model_private_ips" {
  description = "A map of demo model instances to their private IP addresses"
  value       = { for name, inst in aws_instance.demo_model : name => inst.private_ip }
}