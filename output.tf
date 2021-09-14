output "private_ips" {
  value = azurerm_network_interface.internal.*.private_ip_address
}

output "public_ips" {
  value = azurerm_public_ip.external.*.ip_address
}