output "public_ips" {
  value = azurerm_public_ip.nfsblob.*.ip_address
}

output "storage_blob_host" {
  value = azurerm_storage_account.nfsblob.primary_blob_host
}