
resource "aws_eks_node_group" "this" {
  count = var.create ? 1 : 0

  # Required
  cluster_name  = var.cluster_name
  node_role_arn = var.create_iam_role ? aws_iam_role.this[0].arn : var.iam_role_arn
  subnet_ids    = local.create_placement_group ? data.aws_subnets.placement_group[0].ids : var.subnet_ids

  scaling_config {
    min_size     = var.min_size
    max_size     = var.max_size
    desired_size = 3
  }

  # Optional
  node_group_name        = var.use_name_prefix ? null : var.name
  node_group_name_prefix = var.use_name_prefix ? "${var.name}-" : null

  # https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html#launch-template-custom-ami
  ami_type        = var.ami_id != "" ? null : var.ami_type
  release_version = var.ami_id != "" ? null : var.use_latest_ami_release_version ? local.latest_ami_release_version : var.ami_release_version
  version         = var.ami_id != "" ? null : var.cluster_version

  capacity_type        = var.capacity_type
  disk_size            = var.use_custom_launch_template ? null : var.disk_size # if using a custom LT, set disk size on custom LT or else it will error here
  force_update_version = var.force_update_version
  # ML capacity block reservation requires instance type to be set on the launch template
  instance_types = var.capacity_type == "CAPACITY_BLOCK" ? null : var.instance_types
  labels         = var.labels

  dynamic "launch_template" {
    for_each = var.use_custom_launch_template ? [1] : []

    content {
      id      = local.launch_template_id
      version = local.launch_template_version
    }
  }

  dynamic "remote_access" {
    for_each = length(var.remote_access) > 0 ? [var.remote_access] : []

    content {
      ec2_ssh_key               = try(remote_access.value.ec2_ssh_key, null)
      source_security_group_ids = try(remote_access.value.source_security_group_ids, [])
    }
  }

  dynamic "taint" {
    for_each = var.taints

    content {
      key    = taint.value.key
      value  = try(taint.value.value, null)
      effect = taint.value.effect
    }
  }

  dynamic "update_config" {
    for_each = length(var.update_config) > 0 ? [var.update_config] : []

    content {
      max_unavailable_percentage = try(update_config.value.max_unavailable_percentage, null)
      max_unavailable            = try(update_config.value.max_unavailable, null)
    }
  }

  dynamic "node_repair_config" {
    for_each = var.node_repair_config != null ? [var.node_repair_config] : []

    content {
      enabled = node_repair_config.value.enabled
    }
  }

  timeouts {
    create = lookup(var.timeouts, "create", null)
    update = lookup(var.timeouts, "update", null)
    delete = lookup(var.timeouts, "delete", null)
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      scaling_config[0].desired_size,
    ]
  }

  tags = merge(
    var.tags,
    { Name = var.name }
  )
}

#