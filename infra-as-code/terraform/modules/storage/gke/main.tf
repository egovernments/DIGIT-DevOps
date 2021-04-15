resource "google_compute_disk" "default" {
  name  = "${var.disk_prefix}-${count.index}"
  type  = "${var.disk_type}"
  count = "${var.itemCount}"  
  zone  = "${var.region}"
  size = "${var.disk_size_gb}"
  labels = {
    environment = "${var.environment}"
  }
}