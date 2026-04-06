
output "ssh_key_name" {
  value = "${aws_key_pair.ssh_key.key_name}"
  
}