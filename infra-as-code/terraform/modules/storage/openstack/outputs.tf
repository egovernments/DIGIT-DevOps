output "vol_ids" {
  value = "${openstack_blockstorage_volume_v2.vol.*.id}"
}
