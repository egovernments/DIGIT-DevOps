# Create public IPs
resource "azurerm_public_ip" "az_es_eip" {
    name                         = "${var.project}-${var.env}-az-es-eip-${count.index}"
    location                     = "${var.location}"
    resource_group_name          = "${azurerm_resource_group.main.name}"
    allocation_method            = "Dynamic"

    tags {
        environment = "${var.project}-${var.env}"
    }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "az_es_sg" {
    name                = "${var.project}-${var.env}-az-es-sg-${count.index}"
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.main.name}"

    security_rule {
        name                       = "SSH"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    tags {
        environment = "${var.project}-${var.env}"
    }
}

# Create network interface
resource "azurerm_network_interface" "az_es_nic" {
    name                      = "${var.project}-${var.env}-az-es-nic-${count.index}"
    location                  = "${var.location}"
    resource_group_name       = "${azurerm_resource_group.main.name}"
    network_security_group_id = "${azurerm_network_security_group.az_es_sg.id}"

    ip_configuration {
        name                          = "${var.project}-${var.env}-az-es-ipconf-${count.index}"
        subnet_id                     = "${azurerm_subnet.az_dmz.id}"
        private_ip_address_allocation = "dynamic"
        public_ip_address_id          = "${azurerm_public_ip.az_es_eip.id}"
    }

    tags {
        environment = "${var.project}-${var.env}"
    }
}

# Generate random text for a unique storage account name
resource "random_id" "es_randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = "${azurerm_resource_group.main.name}"
    }

    byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "az_es_storage" {
    name                        = "${random_id.es_randomId.hex}"
    resource_group_name         = "${azurerm_resource_group.main.name}"
    location                    = "${var.location}"
    account_tier                = "Standard"
    account_replication_type    = "LRS"

    tags {
        environment = "${var.project}-${var.env}"
    }
}

# Create virtual machine
resource "azurerm_virtual_machine" "az_es_vm" {
    count                 = "${var.elasticsearch["count"]}"
    name                  = "${var.project}-${var.env}-az-vm-es-${count.index}"
    location              = "${var.location}"
    resource_group_name   = "${azurerm_resource_group.main.name}"
    network_interface_ids = ["${azurerm_network_interface.az_es_nic.id}"]
    vm_size               = "${var.elasticsearch["vm_size"]}"
    delete_os_disk_on_termination    = true

    storage_os_disk {
        name              = "${var.project}-${var.env}-az-es-disk-${count.index}"
        caching           = "ReadWrite"
        create_option     = "FromImage"
        managed_disk_type = "Premium_LRS"
        disk_size_gb      = "${var.elasticsearch["volume_size"]}"
    }

    storage_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04.0-LTS"
        version   = "latest"
    }

    os_profile {
        computer_name  = "${var.project}-${var.env}-az-es-${count.index}"
        admin_username       = "${var.elasticsearch["admin_username"]}"
        admin_password       = "${var.elasticsearch["admin_password"]}"
    }

    os_profile_linux_config {
        disable_password_authentication = false
        ssh_keys {
            path     = "/home/azureuser/.ssh/authorized_keys"
            key_data = "${var.ssh_public_key}"
        }
    }

    tags {
        environment = "${var.project}-${var.env}"
    }
}