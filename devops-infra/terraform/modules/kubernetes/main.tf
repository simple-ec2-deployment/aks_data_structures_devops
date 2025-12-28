# Kubernetes Module
# Manages Kubernetes resources including deployments, services, and ingress

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# Namespace
resource "kubernetes_namespace" "app" {
  count = var.namespace != "default" ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      environment = var.environment
      project     = var.project_name
    }
  }
}

# Apply Kubernetes manifests from files
locals {
  namespace = var.namespace != "default" ? kubernetes_namespace.app[0].metadata[0].name : "default"
}

# Frontend Deployment
data "kubectl_file_documents" "frontend" {
  content = file("${var.k8s_dir}/frontend/deployment.yaml")
}

resource "kubectl_manifest" "frontend_deployment" {
  for_each  = data.kubectl_file_documents.frontend.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace
}

# Frontend Service
data "kubectl_file_documents" "frontend_service" {
  content = file("${var.k8s_dir}/frontend/service.yaml")
}

resource "kubectl_manifest" "frontend_service" {
  for_each  = data.kubectl_file_documents.frontend_service.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace

  depends_on = [kubectl_manifest.frontend_deployment]
}

# Frontend HPA
data "kubectl_file_documents" "frontend_hpa" {
  content = file("${var.k8s_dir}/frontend/hpa.yaml")
}

resource "kubectl_manifest" "frontend_hpa" {
  for_each  = data.kubectl_file_documents.frontend_hpa.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace

  depends_on = [kubectl_manifest.frontend_deployment]
}

# Backend Deployment
data "kubectl_file_documents" "backend" {
  content = file("${var.k8s_dir}/backend/deployment.yaml")
}

resource "kubectl_manifest" "backend_deployment" {
  for_each  = data.kubectl_file_documents.backend.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace
}

# Backend Service
data "kubectl_file_documents" "backend_service" {
  content = file("${var.k8s_dir}/backend/service.yaml")
}

resource "kubectl_manifest" "backend_service" {
  for_each  = data.kubectl_file_documents.backend_service.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace

  depends_on = [kubectl_manifest.backend_deployment]
}

# Backend HPA
data "kubectl_file_documents" "backend_hpa" {
  content = file("${var.k8s_dir}/backend/hpa.yaml")
}

resource "kubectl_manifest" "backend_hpa" {
  for_each  = data.kubectl_file_documents.backend_hpa.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace

  depends_on = [kubectl_manifest.backend_deployment]
}

# Data Structure Services
resource "kubectl_manifest" "stack" {
  yaml_body = file("${var.k8s_dir}/data-structures/stack.yaml")
  override_namespace = local.namespace
}

resource "kubectl_manifest" "linkedlist" {
  yaml_body = file("${var.k8s_dir}/data-structures/linkedlist.yaml")
  override_namespace = local.namespace
}

resource "kubectl_manifest" "graph" {
  yaml_body = file("${var.k8s_dir}/data-structures/graph.yaml")
  override_namespace = local.namespace
}

# Ingress
data "kubectl_file_documents" "ingress" {
  content = file("${var.k8s_dir}/ingress/ingress.yaml")
}

resource "kubectl_manifest" "ingress" {
  for_each  = data.kubectl_file_documents.ingress.manifests
  yaml_body = each.value
  
  override_namespace = local.namespace

  depends_on = [
    kubectl_manifest.frontend_service,
    kubectl_manifest.backend_service,
    kubectl_manifest.stack,
    kubectl_manifest.linkedlist,
    kubectl_manifest.graph
  ]
}
