/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "namespace" {
  type = string
}
variable "service_name" {
  type = string
}
variable "chart_name" {
  type = string
  description = "Cert Manager Helm name."
  default = "cert-manager"
}
variable "chart_repo" {
  type = string
  description = "Cert Manager Helm repository name."
  default = "https://charts.jetstack.io"
}
variable "chart_version" {
  type = string
  description = "Cert Manager Helm version."
  default = "1.8.0"
}

# cert-manager is a powerful and extensible X.509 certificate controller for Kubernetes and
# OpenShift workloads. It will obtain certificates from a variety of Issuers, both popular public
# Issuers as well as private Issuers, and ensure the certificates are valid and up-to-date, and
# will attempt to renew certificates at a configured time before expiry.
# (cert-manager manages non-namespaced resources in the cluster and should only be installed once.)
#
# https://cert-manager.io/docs/
#
# Once you've installed cert-manager, you can verify it is deployed correctly by checking the
# cert-manager namespace for running pods:
# $ kubectl get pods --namespace memories
# You should see the cert-manager, cert-manager-cainjector, and cert-manager-webhook pods in a
# Running state.
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
