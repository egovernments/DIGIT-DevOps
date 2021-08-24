#########
# Volume
#########
resource "oci_core_volume" "vol" {
  count               = var.instance_count
  availability_domain = var.ad
  compartment_id      = var.compartment_id
  display_name        = "${var.vol_name}-${count.index}"
  size_in_gbs = var.block_storage_sizes_in_gbs
}
