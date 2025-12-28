# Local Development Terraform Configuration
# Uses the NEW devops-infra structure for deployment

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

provider "kubectl" {
  config_path    = pathexpand("~/.kube/config")
  config_context = "minikube"
}

# Local variables - path to the new kubernetes directory
locals {
  # Go up 3 levels: local -> environments -> terraform -> devops-infra
  # Then into kubernetes
  k8s_root = "${path.module}/../../../kubernetes"
}

# ==========================================
# Ingress Controller (from new location)
# ==========================================
data "kubectl_file_documents" "ingress_controller" {
  content = file("${local.k8s_root}/ingress-controller/nginx-ingress-controller.yaml")
}

resource "kubectl_manifest" "ingress_controller" {
  for_each  = data.kubectl_file_documents.ingress_controller.manifests
  yaml_body = each.value
}

# ==========================================
# Frontend (from new structured folders)
# ==========================================
resource "kubectl_manifest" "frontend_deployment" {
  yaml_body  = file("${local.k8s_root}/frontend/deployment.yaml")
  depends_on = [kubectl_manifest.ingress_controller]
}

resource "kubectl_manifest" "frontend_service" {
  yaml_body  = file("${local.k8s_root}/frontend/service.yaml")
  depends_on = [kubectl_manifest.frontend_deployment]
}

# ==========================================
# Backend (from new structured folders)
# ==========================================
resource "kubectl_manifest" "backend_deployment" {
  yaml_body  = file("${local.k8s_root}/backend/deployment.yaml")
  depends_on = [kubectl_manifest.ingress_controller]
}

resource "kubectl_manifest" "backend_service" {
  yaml_body  = file("${local.k8s_root}/backend/service.yaml")
  depends_on = [kubectl_manifest.backend_deployment]
}

# ==========================================
# Data Structure Services (from migrated location)
# ==========================================
data "kubectl_file_documents" "stack" {
  content = file("${local.k8s_root}/data-structures/stack.yaml")
}

resource "kubectl_manifest" "stack" {
  for_each  = data.kubectl_file_documents.stack.manifests
  yaml_body = each.value
  depends_on = [kubectl_manifest.ingress_controller]
}

data "kubectl_file_documents" "linkedlist" {
  content = file("${local.k8s_root}/data-structures/linkedlist.yaml")
}

resource "kubectl_manifest" "linkedlist" {
  for_each  = data.kubectl_file_documents.linkedlist.manifests
  yaml_body = each.value
  depends_on = [kubectl_manifest.ingress_controller]
}

data "kubectl_file_documents" "graph" {
  content = file("${local.k8s_root}/data-structures/graph.yaml")
}

resource "kubectl_manifest" "graph" {
  for_each  = data.kubectl_file_documents.graph.manifests
  yaml_body = each.value
  depends_on = [kubectl_manifest.ingress_controller]
}

# ==========================================
# Ingress (from new structured folder)
# ==========================================
resource "kubectl_manifest" "ingress" {
  yaml_body = file("${local.k8s_root}/ingress/ingress.yaml")
  depends_on = [
    kubectl_manifest.backend_service,
    kubectl_manifest.frontend_service,
    kubectl_manifest.stack,
    kubectl_manifest.linkedlist,
    kubectl_manifest.graph
  ]
}

# ==========================================
# Outputs
# ==========================================
output "status" {
  value = "Deployment Complete using new devops-infra structure!"
}
