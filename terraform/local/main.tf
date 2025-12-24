# terraform/local/main.tf

locals {
  k8s_dir = "${path.module}/../../k8s"
}

# --- backend.yaml ---
data "kubectl_file_documents" "backend" {
  content = file("${local.k8s_dir}/backend.yaml")
}

resource "kubectl_manifest" "backend" {
  for_each  = data.kubectl_file_documents.backend.manifests
  yaml_body = each.value
}

# --- graph.yaml ---
data "kubectl_file_documents" "graph" {
  content = file("${local.k8s_dir}/graph.yaml")
}

resource "kubectl_manifest" "graph" {
  for_each  = data.kubectl_file_documents.graph.manifests
  yaml_body = each.value
}

# --- linkedlist.yaml ---
data "kubectl_file_documents" "linkedlist" {
  content = file("${local.k8s_dir}/linkedlist.yaml")
}

resource "kubectl_manifest" "linkedlist" {
  for_each  = data.kubectl_file_documents.linkedlist.manifests
  yaml_body = each.value
}

# --- stack.yaml ---
data "kubectl_file_documents" "stack" {
  content = file("${local.k8s_dir}/stack.yaml")
}

resource "kubectl_manifest" "stack" {
  for_each  = data.kubectl_file_documents.stack.manifests
  yaml_body = each.value
}

# --- ui.yaml ---
data "kubectl_file_documents" "ui" {
  content = file("${local.k8s_dir}/ui.yaml")
}

resource "kubectl_manifest" "ui" {
  for_each  = data.kubectl_file_documents.ui.manifests
  yaml_body = each.value
}

# --- ingress.yaml ---
data "kubectl_file_documents" "ingress" {
  content = file("${local.k8s_dir}/ingress.yaml")
}

resource "kubectl_manifest" "ingress" {
  for_each  = data.kubectl_file_documents.ingress.manifests
  yaml_body = each.value
}

# --- nginx-ingress-controller.yaml ---
data "kubectl_file_documents" "ingress_controller" {
  content = file("${local.k8s_dir}/nginx-ingress-controller.yaml")
}

resource "kubectl_manifest" "ingress_controller" {
  for_each  = data.kubectl_file_documents.ingress_controller.manifests
  yaml_body = each.value
}