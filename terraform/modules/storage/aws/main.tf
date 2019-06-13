resource "aws_ebs_volume" "vol" {
  count = "${length(var.availability_zones)}"

  availability_zone = "${var.availability_zones[count.index]}"
  size              = "${var.disk_size_gb}"
  type              = "${var.storage_sku}"

  tags = {
    Name = "${var.disk_prefix}-${count.index}"
    KubernetesCluster = "${var.environment}"
  }
}