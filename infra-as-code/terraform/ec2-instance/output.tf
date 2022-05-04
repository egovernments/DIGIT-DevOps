output "public_ip" {
  value = "${aws_instance.k3d-demo.public_ip}"
}
