provider "azurerm" {
  features {}
}

data "http" "ifconfig" {
  url = "http://ifconfig.me"
}

resource "azurerm_resource_group" "nfsblob" {
  name     = "nfsblob-rg"
  location = "West US 2"
}

resource "random_integer" "nfsblob" {
  min = 100
  max = 999
}

resource "azurerm_virtual_network" "nfsblob" {
  name                = "nfsblob-network"
  address_space       = ["10.80.1.0/24"]
  location            = azurerm_resource_group.nfsblob.location
  resource_group_name = azurerm_resource_group.nfsblob.name
}

resource "azurerm_subnet" "nfsblob" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.nfsblob.name
  virtual_network_name = azurerm_virtual_network.nfsblob.name
  address_prefixes     = ["10.80.1.0/27"]
  service_endpoints    = ["Microsoft.Storage"]
}

resource "azurerm_network_security_group" "nfsblob" {
  name                = "nfsblob-nsg"
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

resource "azurerm_subnet_network_security_group_association" "nfsblob" {
  subnet_id                 = azurerm_subnet.nfsblob.id
  network_security_group_id = azurerm_network_security_group.nfsblob.id
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
    virtual_network_subnet_ids = [azurerm_subnet.nfsblob.id]
  }
}

resource "azurerm_storage_container" "nfsblob" {
  name                  = "myblobs"
  storage_account_name  = azurerm_storage_account.nfsblob.name
  container_access_type = "private"
}

resource "azurerm_public_ip" "nfsblob" {
  count               = 2
  name                = "nfsblob-pip-${count.index + 1}"
  resource_group_name = azurerm_resource_group.nfsblob.name
  location            = azurerm_resource_group.nfsblob.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nfsblob" {
  count               = 2
  name                = "nfsblob-nic-${count.index + 1}"
  location            = azurerm_resource_group.nfsblob.location
  resource_group_name = azurerm_resource_group.nfsblob.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.nfsblob.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.nfsblob[count.index].id
  }
}

resource "azurerm_linux_virtual_machine" "nfsblob" {
  count               = 2
  name                = "nfsblob-vm-${count.index + 1}"
  resource_group_name = azurerm_resource_group.nfsblob.name
  location            = azurerm_resource_group.nfsblob.location
  size                = "Standard_B2ms"
  admin_username      = "azadmin"
  network_interface_ids = [
    azurerm_network_interface.nfsblob[count.index].id,
  ]

  admin_ssh_key {
    username   = "azadmin"
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
}