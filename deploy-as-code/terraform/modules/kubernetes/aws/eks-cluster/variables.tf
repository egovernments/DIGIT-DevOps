variable "cluster_name" {
}

variable "vpc_id" {
}

variable "subnets" {
    type = list(string)
}

variable "kubernetes_version" {
}

variable "master_nodes_security_grp_ids" {
    type = list(string)
}