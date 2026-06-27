terraform {
  required_version = ">= 1.15.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {}
}

data "http" "current_ip" {
  url = "https://api.ipify.org"
}

variable "resource_group_name" {
  type    = string
  default = "ts"
}

variable "vm_name" {
  type    = string
  default = "ts-vm"
}

variable "vm_location" {
  type    = string
  description = "Azure region where the VM will be deployed."
}

variable "admin_username" {
  type    = string
  description = "Admin username for the VM."
}

variable "ssh_port" {
  type    = number
  description = "Alternative SSH port for accessing the VM."
}

variable "ssh_public_key" {
  type        = string
  description = "Public SSH key used to access the VM after deployment."
}

variable "vm_size" {
  type    = string
  default = "Standard_B2ats_v2"
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.vm_location
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.vm_name}"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_subnet" "this" {
  name                 = "subnet-${var.vm_name}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_public_ip" "this" {
  name                = "public-ip-${var.vm_name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "this" {
  name                = "nsg-${var.vm_name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "default-ssh"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${chomp(data.http.current_ip.response_body)}/32"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "custom-ssh"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "${var.ssh_port}"
    source_address_prefix      = "${chomp(data.http.current_ip.response_body)}/32"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ts-voice"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "9987"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ts-file-transfer"
    priority                   = 1030
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30033"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "this" {
  name                = "nic-${var.vm_name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }
}

resource "azurerm_network_interface_security_group_association" "this" {
  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_linux_virtual_machine" "this" {
  name                            = var.vm_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  network_interface_ids           = [azurerm_network_interface.this.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    disk_size_gb         = 32
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Debian"
    offer     = "debian-13"
    sku       = "13-gen2"
    version   = "latest"
  }
}

output "public_ip_address" {
  value = azurerm_public_ip.this.ip_address
}

output "ssh_command" {
  description = "You should be able to access the provisioned VM via SSH shortly..."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.this.ip_address}"
}
