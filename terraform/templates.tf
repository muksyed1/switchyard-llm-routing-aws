resource "local_file" "inventory_ini" {
  content  = local.content
  filename = "${path.module}/../ansible/inventory.ini"
}