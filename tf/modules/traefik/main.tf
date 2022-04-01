/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "namespace" {
  type = string
}
variable "ingress_controller_chart_name" {
  type = string
  description = "Ingress Controller Helm chart name."
  default = "traefik"
}
variable "ingress_controller_chart_repo" {
  type = string
  description = "Ingress Controller Helm repository name."
  default = "https://helm.traefik.io/traefik"
}
variable "ingress_controller_chart_version" {
  type = string
  description = "Ingress Controller Helm repository version."
  default = "10.0.0"
}

resource "null_resource" "scc-traefik" {
  provisioner "local-exec" {
    command = "oc apply -f ./utility-files/traefik/mem-traefik-scc.yaml"
  }
  #
  provisioner "local-exec" {
    when = destroy
    command = "oc delete scc mem-traefik-scc"
  }
}

# Deploy the Ingress Controller Traefik.
resource "helm_release" "ingress_controller" {
  name = var.ingress_controller_chart_name
  chart = var.ingress_controller_chart_name
  repository = var.ingress_controller_chart_repo
  version = var.ingress_controller_chart_version
  namespace = var.namespace
  values = [file("./utility-files/traefik/traefik.yml")]
}
