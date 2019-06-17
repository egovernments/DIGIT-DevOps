# Configure the Microsoft Azure Provider
provider "azurerm" {
    subscription_id = "${var.SUBSCRIPTION_ID}"
    client_id       = "${var.CLIENT_ID}"
    client_secret   = "${var.CLIENT_SECRET}"
    tenant_id       = "${var.TENANT_ID}"
}

module "az_group" {
    source = "resources"
    env = "${var.env}"
    resourcename = "${var.project}-${env}-az-cluster"
    project = "${var.project}"
    location = "${var.location}"
    dmz_cidrs = "${var.dmz_cidrs}"
    az_cidr = "${var.az_cidr}"
    ssh_public_key = "${var.ssh_public_key}"
    
    frontend = "${var.frontend}"
    application = "${var.application}"
    elasticsearch = "${var.elasticsearch}"
    postgresql = "${var.postgresql}"
}