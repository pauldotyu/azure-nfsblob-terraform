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

resource "azurerm_subnet" "public" {
  name                 = "public"
  resource_group_name  = azurerm_resource_group.nfsblob.name
  virtual_network_name = azurerm_virtual_network.nfsblob.name
  address_prefixes     = ["10.80.1.0/27"]
  service_endpoints    = ["Microsoft.Storage"]
}


resource "azurerm_network_security_group" "public" {
  name                = "nsg-nfsblob-public"
  location            = azurerm_resource_group.nfsblob.location
  resource_group_name = azurerm_resource_group.nfsblob.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = data.http.ifconfig.body
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.public.id
}

resource "azurerm_storage_account" "nfsblob" {
  name                = "sanfsblob${random_integer.nfsblob.result}"
  resource_group_name = azurerm_resource_group.nfsblob.name

  location                  = azurerm_resource_group.nfsblob.location
  account_tier              = "Standard"
  account_replication_type  = "ZRS"
  enable_https_traffic_only = true
  is_hns_enabled            = true # This can only be true when account_tier is Standard or when account_tier is Premium and account_kind is BlockBlobStorage
  nfsv3_enabled             = true # This can only be true when account_tier is Standard and account_kind is StorageV2, or account_tier is Premium and account_kind is BlockBlobStorage. Additionally, the is_hns_enabled is true, and enable_https_traffic_only is false.

  network_rules {
    default_action = "Deny"

    ip_rules = [
      data.http.ifconfig.body
    ]

    virtual_network_subnet_ids = [
      azurerm_subnet.public.id
    ]
  }

  depends_on = [
    azurerm_subnet.public
  ]
}

resource "azurerm_storage_container" "nfsblob" {
  name                  = "myblobs"
  storage_account_name  = azurerm_storage_account.nfsblob.name
  container_access_type = "private"
}

resource "azurerm_public_ip" "nfsblob" {
  count               = 2
  name                = "vm-nfsblob-${count.index + 1}-pip"
  resource_group_name = azurerm_resource_group.nfsblob.name
  location            = azurerm_resource_group.nfsblob.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nfsblob" {
  count               = 2
  name                = "vm-nfsblob-${count.index + 1}-nic"
  location            = azurerm_resource_group.nfsblob.location
  resource_group_name = azurerm_resource_group.nfsblob.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.nfsblob[count.index].id
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.public
  ]
}

resource "azurerm_linux_virtual_machine" "nfsblob" {
  count               = 2
  name                = "vm-nfsblob-${count.index + 1}"
  resource_group_name = azurerm_resource_group.nfsblob.name
  location            = azurerm_resource_group.nfsblob.location
  size                = "Standard_B2ms"
  admin_username      = var.vm_username

  network_interface_ids = [
    azurerm_network_interface.nfsblob[count.index].id,
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
    azurerm_private_dns_zone_virtual_network_link.nfsblob
  ]
}

resource "azurerm_subnet" "private" {
  name                                           = "private"
  resource_group_name                            = azurerm_resource_group.nfsblob.name
  virtual_network_name                           = azurerm_virtual_network.nfsblob.name
  address_prefixes                               = ["10.80.1.32/27"]
  enforce_private_link_endpoint_network_policies = false
}

resource "azurerm_private_dns_zone" "nfsblob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.nfsblob.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "nfsblob" {
  name                  = "${azurerm_virtual_network.nfsblob.name}-link"
  resource_group_name   = azurerm_resource_group.nfsblob.name
  private_dns_zone_name = azurerm_private_dns_zone.nfsblob.name
  virtual_network_id    = azurerm_virtual_network.nfsblob.id

  depends_on = [
    azurerm_private_endpoint.nfsblob
  ]
}

resource "azurerm_private_endpoint" "nfsblob" {
  name                = "sanfsblob${random_integer.nfsblob.result}-pe"
  resource_group_name = azurerm_resource_group.nfsblob.name
  location            = azurerm_resource_group.nfsblob.location
  subnet_id           = azurerm_subnet.private.id

  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.nfsblob.id
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
    azurerm_storage_account.nfsblob,
    azurerm_private_dns_zone.nfsblob
  ]
}

resource "azurerm_network_security_group" "private" {
  name                = "nsg-nfsblob-private"
  location            = azurerm_resource_group.nfsblob.location
  resource_group_name = azurerm_resource_group.nfsblob.name

  security_rule {
    name                       = "AllowPublicToPrivate"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = azurerm_network_interface.nfsblob[0].private_ip_address #only allow first nic through
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