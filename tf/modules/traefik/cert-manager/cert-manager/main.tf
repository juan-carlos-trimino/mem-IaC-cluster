/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable namespace {
  type = string
}
variable service_name {
  type = string
}
variable chart_version {
  type = string
  description = "Cert Manager Helm version."
}
variable chart_name {
  type = string
  description = "Cert Manager Helm name."
  default = "cert-manager"
}
variable chart_repo {
  type = string
  description = "Cert Manager Helm repository name."
  default = "https://charts.jetstack.io"
}

resource "helm_release" "cert_manager" {
  name = var.service_name
  repository = var.chart_repo
  chart = var.chart_name
  version = var.chart_version
  namespace = var.namespace
  create_namespace = false
  # To automatically install and manage the CRDs as part of your Helm release, you must add the
  # --set installCRDs=true flag to your Helm installation command.
  set {
    name = "installCRDs"
    value = true
  }
}
