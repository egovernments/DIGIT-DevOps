resource "aws_ebs_volume" "vol" {
  count = "${var.storage_count}"

  availability_zone = "${element(var.availability_zones, count.index)}"
  size              = "${var.disk_size_gb}"
  type              = "${var.storage_sku}"

  tags = {
    Name = "${var.disk_prefix}-${count.index}"
    KubernetesCluster = "${var.environment}"
  }
}