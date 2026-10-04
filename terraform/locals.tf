locals {
  gateway_ports  = ["22", "3000", "4000", "9090"]
  model_ports    = ["22"]
  model_sg_ports = ["11434", "9100"]
  cidr_ipv4      = "${chomp(data.http.my_ip.response_body)}/32"
}

locals {
  demo_models = {
    demo-model-nemotron = "nemotron-mini"
    demo-model-llama    = "llama3.2:3b"
    demo-model-qwen     = "qwen3:4b"
  }
}

locals {
  # Render the template file into a local variable string
  content = templatefile("${path.module}/inventory.tftpl", {
    gateway_ip = aws_instance.demo_gateway.public_ip
    models     = aws_instance.demo_model
  })
}