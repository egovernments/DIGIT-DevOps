# Node Stability Improvements for EKS Cluster
# This configuration addresses frequent node replacements

# Updated variables for better stability
variable "on_demand_base_capacity" {
  description = "Number of On-Demand instances to maintain as baseline"
  default = 1
}

variable "on_demand_percentage" {
  description = "Percentage of On-Demand instances above base capacity"
  default = 25  # 25% On-Demand, 75% Spot for better stability
}

variable "spot_max_price" {
  description = "Maximum price for Spot instances (empty for market price)"
  default = ""  # Use market price, but we'll set reasonable limits
}

# Improved instance type selection for better Spot availability
variable "stable_instance_types" {
  description = "Instance types optimized for Spot stability"
  default = [
    "m5.xlarge",     # Most stable and widely available
    "m5d.xlarge",    # Good alternative with local storage
    "c5.xlarge",     # Compute optimized, usually cheaper
    "r5.xlarge",     # Memory optimized
    "m5a.xlarge",    # AMD variant, often better availability
    "c5n.xlarge"     # Network optimized, good availability
  ]
}

# Enhanced Auto Scaling Group configuration
locals {
  stable_asg_config = {
    # Improved health check settings
    health_check_grace_period = 300  # 5 minutes instead of 15 seconds
    health_check_type        = "ELB"  # Use ELB health checks for better accuracy
    
    # Better termination policies
    termination_policies = [
      "OldestInstance",           # Terminate oldest first
      "AllocationStrategy",       # Maintain allocation strategy
      "ClosestToNextInstanceHour" # Cost optimization
    ]
    
    # Capacity rebalancing settings
    capacity_rebalance = true
    max_instance_lifetime = 604800  # 7 days max lifetime
    
    # Instance distribution for stability
    instances_distribution = {
      on_demand_allocation_strategy                = "prioritized"
      on_demand_base_capacity                     = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity    = var.on_demand_percentage
      spot_allocation_strategy                    = "diversified"  # Better than price-capacity-optimized for stability
      spot_instance_pools                         = 4             # Use 4 different pools
      spot_max_price                             = ""             # Use market price
    }
  }
}

# Spot Fleet Request configuration for additional stability
resource "aws_spot_fleet_request" "stable_spot_fleet" {
  count                          = 0  # Disabled by default, enable if needed
  iam_fleet_role                = aws_iam_role.spot_fleet_role[0].arn
  allocation_strategy           = "diversified"
  target_capacity              = 2
  spot_price                   = "0.12"  # Set reasonable max price
  terminate_instances_with_expiration = true
  
  launch_specification {
    image_id             = data.aws_ami.eks_worker.id
    instance_type        = "m5.xlarge"
    key_name            = var.key_name
    vpc_security_group_ids = [module.eks.node_security_group_id]
    subnet_id           = module.network.private_subnets[0]
    
    user_data = base64encode(templatefile("${path.module}/userdata.sh", {
      cluster_name = var.cluster_name
      endpoint     = module.eks.cluster_endpoint
      ca_data      = module.eks.cluster_certificate_authority_data
    }))
  }
  
  launch_specification {
    image_id             = data.aws_ami.eks_worker.id
    instance_type        = "c5.xlarge"
    key_name            = var.key_name
    vpc_security_group_ids = [module.eks.node_security_group_id]
    subnet_id           = module.network.private_subnets[1]
    
    user_data = base64encode(templatefile("${path.module}/userdata.sh", {
      cluster_name = var.cluster_name
      endpoint     = module.eks.cluster_endpoint
      ca_data      = module.eks.cluster_certificate_authority_data
    }))
  }
  
  tags = {
    Name = "${var.cluster_name}-stable-spot-fleet"
  }
}

# IAM role for Spot Fleet (if using Spot Fleet)
resource "aws_iam_role" "spot_fleet_role" {
  count = 0  # Disabled by default
  name  = "${var.cluster_name}-spot-fleet-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "spotfleet.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "spot_fleet_policy" {
  count      = 0  # Disabled by default
  role       = aws_iam_role.spot_fleet_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetRequestRole"
}

# Node termination handler for graceful shutdowns
resource "kubernetes_daemonset" "aws_node_termination_handler" {
  metadata {
    name      = "aws-node-termination-handler"
    namespace = "kube-system"
    labels = {
      app = "aws-node-termination-handler"
    }
  }
  
  spec {
    selector {
      match_labels = {
        app = "aws-node-termination-handler"
      }
    }
    
    template {
      metadata {
        labels = {
          app = "aws-node-termination-handler"
        }
      }
      
      spec {
        service_account_name = kubernetes_service_account.aws_node_termination_handler.metadata[0].name
        host_network = true
        dns_policy = "ClusterFirstWithHostNet"
        
        container {
          name  = "aws-node-termination-handler"
          image = "public.ecr.aws/aws-ec2/aws-node-termination-handler:v1.21.0"
          
          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          
          env {
            name  = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          
          env {
            name  = "NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }
          
          env {
            name  = "SPOT_POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }
          
          env {
            name  = "DELETE_LOCAL_DATA"
            value = "true"
          }
          
          env {
            name  = "IGNORE_DAEMON_SETS"
            value = "true"
          }
          
          env {
            name  = "POD_TERMINATION_GRACE_PERIOD"
            value = "30"
          }
          
          env {
            name  = "INSTANCE_METADATA_URL"
            value = "http://169.254.169.254"
          }
          
          resources {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
          
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root           = true
            run_as_user               = 1000
            run_as_group              = 1000
          }
        }
        
        node_selector = {
          "kubernetes.io/os" = "linux"
        }
        
        toleration {
          operator = "Exists"
        }
      }
    }
  }
  
  depends_on = [kubernetes_service_account.aws_node_termination_handler]
}

# Service account for node termination handler
resource "kubernetes_service_account" "aws_node_termination_handler" {
  metadata {
    name      = "aws-node-termination-handler"
    namespace = "kube-system"
    labels = {
      app = "aws-node-termination-handler"
    }
  }
}

# Cluster role for node termination handler
resource "kubernetes_cluster_role" "aws_node_termination_handler" {
  metadata {
    name = "aws-node-termination-handler"
  }
  
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "patch", "update"]
  }
  
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["list", "get"]
  }
  
  rule {
    api_groups = [""]
    resources  = ["pods/eviction"]
    verbs      = ["create"]
  }
  
  rule {
    api_groups = ["extensions", "apps"]
    resources  = ["daemonsets"]
    verbs      = ["get"]
  }
  
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }
}

# Cluster role binding for node termination handler
resource "kubernetes_cluster_role_binding" "aws_node_termination_handler" {
  metadata {
    name = "aws-node-termination-handler"
  }
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.aws_node_termination_handler.metadata[0].name
  }
  
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.aws_node_termination_handler.metadata[0].name
    namespace = "kube-system"
  }
}
