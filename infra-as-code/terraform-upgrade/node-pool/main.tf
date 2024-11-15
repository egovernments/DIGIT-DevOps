data "aws_security_group" "node_sg" {
 tags = {
    Name = "${var.cluster_name}-eks_worker_sg"
  }
}
  
module "node-group" {  
  for_each = toset(["digit"])
  source = "../modules/node-pool/aws"

  cluster_name        = "${var.cluster_name}"
  node_group_name     = "${each.key}-ng"
  kubernetes_version  = "${var.kubernetes_version}"
  security_groups     =  ["${data.aws_security_group.node_sg.id}"]
  subnet              = "${concat(slice(module.network.private_subnets, 0, length(var.node_pool_zone)))}"
  node_group_max_size = 1
  node_group_desired_size = 1

}