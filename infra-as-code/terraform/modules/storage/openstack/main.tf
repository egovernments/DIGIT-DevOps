resource "openstack_blockstorage_volume_v2" "vol" {
  count       = "${var.itemCount}"
  name        = "${var.disk_prefix}-${count.index}"
  size        = "${var.disk_size_gb}"

  metadata = {
    Name = "${var.disk_prefix}-${count.index}"
    KubernetesCluster = "${var.environment}"
  }  
}