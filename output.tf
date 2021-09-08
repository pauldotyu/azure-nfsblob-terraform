output "public_ips" {
  value = azurerm_public_ip.nfsblob.*.ip_address
}