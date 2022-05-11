output "public_ip" {
  value = "${aws_instance.digit-quickstart-vm.public_ip}"
}
