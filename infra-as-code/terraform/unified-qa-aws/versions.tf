terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.37.1"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 3.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
    http = {
      source = "hashicorp/http"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0"
    }
  }
}
