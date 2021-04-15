output "volume_ids" {
  value = "${aws_ebs_volume.vol.*.id}"
}

output "volume_arns" {
  value = "${aws_ebs_volume.vol.*.arn}"
}