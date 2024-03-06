provider "aws" {
  region = "${var.region}"
  profile = "digit-infra-aws"
}
module "ssh_key" {
  source             = "../modules/Instance/aws-ec2"
  key_name           =  "${var.key_name}"
  public_key         =  "${var.public_key}"
} 

resource "aws_instance" "digit-quickstart-vm" {
  ami                    = "${var.ami_name_value}"
  instance_type          = "${var.instance_type}"
  key_name               = module.ssh_key.ssh_key_name
  monitoring             =  false
  associate_public_ip_address = true
  availability_zone      =  "ap-south-1b"

  tags = {
    Name = "${var.tag}"
  }
}
