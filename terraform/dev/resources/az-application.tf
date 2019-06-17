# Create public IPs
resource "azurerm_public_ip" "az_app_eip" {
    name                         = "${var.project}-${var.env}-az-app-eip-${count.index}"
    location                     = "${var.location}"
    resource_group_name          = "${azurerm_resource_group.main.name}"
    allocation_method            = "Dynamic"

    tags {
        environment = "${var.project}-${var.env}"
    }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "az_app_sg" {
    name                = "${var.project}-${var.env}-az-app-sg-${count.index}"
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
resource "azurerm_network_interface" "az_app_nic" {
    name                      = "${var.project}-${var.env}-az-app-nic-${count.index}"
    location                  = "${var.location}"
    resource_group_name       = "${azurerm_resource_group.main.name}"
    network_security_group_id = "${azurerm_network_security_group.az_app_sg.id}"

    ip_configuration {
        name                          = "${var.project}-${var.env}-az-app-ipconf-${count.index}"
        subnet_id                     = "${azurerm_subnet.az_dmz.id}"
        private_ip_address_allocation = "dynamic"
        public_ip_address_id          = "${azurerm_public_ip.az_app_eip.id}"
    }

    tags {
        environment = "${var.project}-${var.env}"
    }
}

# Generate random text for a unique storage account name
resource "random_id" "app_randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = "${azurerm_resource_group.main.name}"
    }

    byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "az_app_storage" {
    name                        = "${random_id.app_randomId.hex}"
    resource_group_name         = "${azurerm_resource_group.main.name}"
    location                    = "${var.location}"
    account_tier                = "Standard"
    account_replication_type    = "LRS"

    tags {
        environment = "${var.project}-${var.env}"
    }
}

# Create virtual machine
resource "azurerm_virtual_machine" "az_app_vm" {
    count                 = "${var.application["count"]}"
    name                  = "${var.project}-${var.env}-az-vm-app-${count.index}"
    location              = "${var.location}"
    resource_group_name   = "${azurerm_resource_group.main.name}"
    network_interface_ids = ["${azurerm_network_interface.az_app_nic.id}"]
    vm_size               = "${var.application["vm_size"]}"
    delete_os_disk_on_termination    = true

    storage_os_disk {
        name              = "${var.project}-${var.env}-az-app-disk-${count.index}"
        caching           = "ReadWrite"
        create_option     = "FromImage"
        managed_disk_type = "Premium_LRS"
        disk_size_gb      = "${var.application["volume_size"]}"
    }

    storage_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04.0-LTS"
        version   = "latest"
    }

    os_profile {
        computer_name  = "${var.project}-${var.env}-az-app-${count.index}"
        admin_username       = "${var.application["admin_username"]}"
        admin_password       = "${var.application["admin_password"]}"
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

#resource "azurerm_dns_zone" "app_dns" {
#  name                = "${var.project}-${var.env}-app.az.com"
#  resource_group_name = "${azurerm_resource_group.main.name}"
#}

#resource "azurerm_dns_a_record" "app_record" {
#  name                = "${var.project}-${var.env}-app"
#  zone_name           = "${azurerm_dns_zone.app_dns.name}"
#  resource_group_name = "${azurerm_resource_group.main.name}"
#  ttl                 = 300
#  records             = ["${azurerm_network_interface.az_app_nic.private_ip_address}"]
#}