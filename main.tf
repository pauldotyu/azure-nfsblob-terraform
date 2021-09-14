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
  subnet_id                 = azurerm_subnet.external.id
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
    virtual_network_subnet_ids = [azurerm_subnet.internal.id]
  }
}

resource "azurerm_storage_container" "nfsblob" {
  name                  = "myblobs"
  storage_account_name  = azurerm_storage_account.nfsblob.name
  container_access_type = "private"
}

resource "azurerm_network_interface" "internal" {
  count               = 2
  name                = "nfsblob-int-nic-${count.index + 1}"
  location            = azurerm_resource_group.nfsblob.location
  resource_group_name = azurerm_resource_group.nfsblob.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "internal" {
  count               = 2
  name                = "vmnfsblobint-${count.index + 1}"
  resource_group_name = azurerm_resource_group.nfsblob.name
  location            = azurerm_resource_group.nfsblob.location
  size                = "Standard_B2ms"
  admin_username      = "azadmin"
  network_interface_ids = [
    azurerm_network_interface.internal[count.index].id,
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

resource "azurerm_public_ip" "external" {
  count               = 1
  name                = "nfsblob-ext-pip-${count.index + 1}"
  resource_group_name = azurerm_resource_group.nfsblob.name
  location            = azurerm_resource_group.nfsblob.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "external" {
  count               = 1
  name                = "nfsblob-ext-nic-${count.index + 1}"
  location            = azurerm_resource_group.nfsblob.location
  resource_group_name = azurerm_resource_group.nfsblob.name

  ip_configuration {
    name                          = "external"
    subnet_id                     = azurerm_subnet.external.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.external[count.index].id
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.nfsblob
  ]
}

resource "azurerm_linux_virtual_machine" "external" {
  count               = 1
  name                = "vmnfsblobext-${count.index + 1}"
  resource_group_name = azurerm_resource_group.nfsblob.name
  location            = azurerm_resource_group.nfsblob.location
  size                = "Standard_B2ms"
  admin_username      = "azadmin"
  network_interface_ids = [
    azurerm_network_interface.external[count.index].id,
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