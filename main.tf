provider "azurerm" {
  features {}
}

data "http" "ifconfig" {
  url = "http://ifconfig.me"
}

resource "azurerm_resource_group" "nfsblob" {
  name     = "rg-nfsblob"
  location = "West US 2"
}

resource "random_integer" "nfsblob" {
  min = 100
  max = 999
}

resource "azurerm_virtual_network" "nfsblob" {
  name                = "vn-nfsblob"
  address_space       = ["10.80.1.0/24"]
  location            = azurerm_resource_group.nfsblob.location
  resource_group_name = azurerm_resource_group.nfsblob.name
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.nfsblob.name
  virtual_network_name = azurerm_virtual_network.nfsblob.name
  address_prefixes     = ["10.80.1.0/27"]
  service_endpoints    = ["Microsoft.Storage"]
}


resource "azurerm_subnet" "external" {
  name                 = "external"
  resource_group_name  = azurerm_resource_group.nfsblob.name
  virtual_network_name = azurerm_virtual_network.nfsblob.name
  address_prefixes     = ["10.80.1.32/27"]
  service_endpoints    = ["Microsoft.Storage"]
}

resource "azurerm_network_security_group" "external" {
  name                = "nsg-nfsblob-external"
  location            = azurerm_resource_group.nfsblob.location
  resource_group_name = azurerm_resource_group.nfsblob.name

  security_rule {
    name                       = "AllowMe"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = data.http.ifconfig.body
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "external" {
  subnet_id                 = azurerm_subnet.external.id
  network_security_group_id = azurerm_network_security_group.external.id
}

resource "azurerm_storage_account" "nfsblob" {
  name                = "sanfsblob${random_integer.nfsblob.result}"
  resource_group_name = azurerm_resource_group.nfsblob.name

  location                  = azurerm_resource_group.nfsblob.location
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  enable_https_traffic_only = true
  is_hns_enabled            = true # This can only be true when account_tier is Standard or when account_tier is Premium and account_kind is BlockBlobStorage
  nfsv3_enabled             = true # This can only be true when account_tier is Standard and account_kind is StorageV2, or account_tier is Premium and account_kind is BlockBlobStorage. Additionally, the is_hns_enabled is true, and enable_https_traffic_only is false.

  network_rules {
    default_action = "Deny"

    ip_rules = [
      data.http.ifconfig.body
    ]

    virtual_network_subnet_ids = [
      azurerm_subnet.internal.id,
      azurerm_subnet.external.id
    ]
  }

  depends_on = [
    azurerm_subnet.internal,
    azurerm_subnet.external
  ]
}

resource "azurerm_storage_container" "nfsblob" {
  name                  = "myblobs"
  storage_account_name  = azurerm_storage_account.nfsblob.name
  container_access_type = "private"
}

resource "azurerm_network_interface" "internal" {
  count               = 1
  name                = "vm-nfsblobint-${count.index + 1}-nic"
  location            = azurerm_resource_group.nfsblob.location
  resource_group_name = azurerm_resource_group.nfsblob.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "internal" {
  count               = 1
  name                = "vm-nfsblobint-${count.index + 1}"
  resource_group_name = azurerm_resource_group.nfsblob.name
  location            = azurerm_resource_group.nfsblob.location
  size                = "Standard_B2ms"
  admin_username      = var.vm_username
  network_interface_ids = [
    azurerm_network_interface.internal[count.index].id,
  ]

  admin_password                  = var.vm_password
  disable_password_authentication = false

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.private
  ]
}

resource "azurerm_public_ip" "external" {
  count               = 2
  name                = "vm-nfsblobext-${count.index + 1}-pip"
  resource_group_name = azurerm_resource_group.nfsblob.name
  location            = azurerm_resource_group.nfsblob.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "external" {
  count               = 2
  name                = "vm-nfsblobext-${count.index + 1}-nic"
  location            = azurerm_resource_group.nfsblob.location
  resource_group_name = azurerm_resource_group.nfsblob.name

  ip_configuration {
    name                          = "external"
    subnet_id                     = azurerm_subnet.external.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.external[count.index].id
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.external
  ]
}

resource "azurerm_linux_virtual_machine" "external" {
  count               = 2
  name                = "vm-nfsblobext-${count.index + 1}"
  resource_group_name = azurerm_resource_group.nfsblob.name
  location            = azurerm_resource_group.nfsblob.location
  size                = "Standard_B2ms"
  admin_username      = var.vm_username
  network_interface_ids = [
    azurerm_network_interface.external[count.index].id,
  ]

  admin_ssh_key {
    username   = var.vm_username
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.private
  ]
}


resource "azurerm_subnet" "private" {
  name                                           = "private"
  resource_group_name                            = azurerm_resource_group.nfsblob.name
  virtual_network_name                           = azurerm_virtual_network.nfsblob.name
  address_prefixes                               = ["10.80.1.64/27"]
  enforce_private_link_endpoint_network_policies = false
}

resource "azurerm_private_dns_zone" "private" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.nfsblob.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "private" {
  name                  = "vn-privatelink.blob.core.windows.net"
  resource_group_name   = azurerm_resource_group.nfsblob.name
  private_dns_zone_name = azurerm_private_dns_zone.private.name
  virtual_network_id    = azurerm_virtual_network.nfsblob.id

  depends_on = [
    azurerm_private_endpoint.private
  ]
}

resource "azurerm_private_endpoint" "private" {
  name                = "sanfsblob${random_integer.nfsblob.result}-pe"
  resource_group_name = azurerm_resource_group.nfsblob.name
  location            = azurerm_resource_group.nfsblob.location
  subnet_id           = azurerm_subnet.private.id

  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.private.id
    ]
  }

  private_service_connection {
    name                           = "sanfsblob${random_integer.nfsblob.result}-pe"
    private_connection_resource_id = azurerm_storage_account.nfsblob.id
    is_manual_connection           = false
    subresource_names = [
      "blob"
    ]
  }

  depends_on = [
    azurerm_subnet.private,
    azurerm_private_dns_zone.private,
    azurerm_storage_account.nfsblob
  ]
}

resource "azurerm_network_security_group" "private" {
  name                = "nsg-nfsblob-private"
  location            = azurerm_resource_group.nfsblob.location
  resource_group_name = azurerm_resource_group.nfsblob.name

  security_rule {
    name                       = "AllowExternalToPrivate"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = azurerm_network_interface.external[0].private_ip_address #only allow first nic through
    destination_address_prefix = "*"
  }

  security_rule {
    name                         = "DenyAllElse"
    priority                     = 101
    direction                    = "Inbound"
    access                       = "Deny"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "*"
    source_address_prefix        = "*"
    destination_address_prefixes = azurerm_subnet.private.address_prefixes
  }
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.private.id
}