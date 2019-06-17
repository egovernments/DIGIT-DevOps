
# Create a resource group if it doesn’t exist
resource "azurerm_resource_group" "main" {
    name     = "${var.project}-${var.env}-az-resources"
    location = "${var.location}"

    tags {
        environment = "${var.project}-${var.env}"
    }
}

# Create virtual network
resource "azurerm_virtual_network" "az_main_cidr" {
    name                = "${var.project}-${var.env}-az-network"
    address_space       = ["${var.az_cidr}"]
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.main.name}"

    tags {
        environment = "${var.project}-${var.env}"
    }
}

# Create subnet
resource "azurerm_subnet" "az_dmz" {
    name                 = "${var.project}-${var.env}-sn-public"
    resource_group_name  = "${azurerm_resource_group.main.name}"
    virtual_network_name = "${azurerm_virtual_network.az_main_cidr.name}"
    address_prefix       = "${var.dmz_cidrs}"
}