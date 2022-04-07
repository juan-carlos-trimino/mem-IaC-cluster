/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "app_name" {
  type = string
}
variable "namespace" {
  type = string
}
variable "traefik_secret" {
  type = string
}
variable "ingress_controller_chart_name" {
  type = string
  description = "Ingress Controller Helm chart name."
  default = "traefik"
}
variable "ingress_controller_chart_repo" {
  type = string
  description = "Using the official Traefik helm chart (Ingress Controller)."
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
# Notes:
# 1. By default, the chart will deploy Traefik in LoadBalancer mode.
resource "helm_release" "ingress_controller" {
  name = var.ingress_controller_chart_name
  chart = var.ingress_controller_chart_name
  repository = var.ingress_controller_chart_repo
  version = var.ingress_controller_chart_version
  namespace = var.namespace
  values = [file("./utility-files/traefik/traefik.yml")]
}

resource "kubernetes_secret" "secret" {
  metadata {
    name = "traefik-dashboard-auth-secret"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  # Plain-text data.
  # RabbitMQ nodes and the CLI tools use a cookie to determine whether they are allowed to
  # communicate with each other. For two nodes to be able to communicate, they must have the same
  # shared secret called the Erlang cookie.
  data = {
    users = "${var.traefik_secret}"
  }
  type = "Opaque"
}
