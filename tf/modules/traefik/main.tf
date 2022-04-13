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
  depends_on = [
    helm_release.ingress_controller
  ]
  provisioner "local-exec" {
    command = "oc apply -f ./utility-files/traefik/mem-traefik-scc.yaml"
  }
  #
  provisioner "local-exec" {
    when = destroy
    command = "oc delete scc mem-traefik-scc"
  }
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
  data = {
    users = "${var.traefik_secret}"
  }
  type = "Opaque"
}

# Traefik is a Cloud Native Edge Router that will work as an ingress controller to a Kubernetes
# cluster. It will be responsible to make sure that when the traffic from a web application hits
# the Kubernetes cluster, it will go to the right Service. Also, it makes it very easy to assign
# an SSL/TLS certificate to the web application.
#
# Notes:
# 1. To watch the traefik's logs:
#    $ kubectl logs -n memories -l app.kubernetes.io/name=traefik -f
# 2. Traefik supports the ACME protocol used by Let's Encrypt.
# 3. By default, the chart will deploy Traefik in LoadBalancer mode.
# 4. EntryPoints are the network entry points into Traefik. They define the port which will receive
#    the packets, and whether to listen for TCP or UDP. The Traefik Helm chart deployment creates
#    the following entrypoints:
#    * web: It is used for all HTTP requests. The Kubernetes LoadBalancer service maps port 80 to
#           the web entrypoint.
#    * websecure: It is used for all HTTPS requests. The Kubernetes LoadBalancer service maps port
#                 443 to the websecure entrypoint.
#    * traefik: Kubernetes uses the Traefik Proxy entrypoint for pod liveliness check. The Traefik
#               dashboard and API are available on the Traefik entrypoint.
#    Applications are configured either on the web or the websecure entrypoints.
#    web - port 8000 (exposed as port 80)
#    websecure - port 8443 (exposed as port 443)
#    traefik - port 9000 (not exposed)
#    metrics - port 9100 (not exposed)
resource "helm_release" "ingress_controller" {
  name = var.ingress_controller_chart_name
  chart = var.ingress_controller_chart_name
  repository = var.ingress_controller_chart_repo
  version = var.ingress_controller_chart_version
  namespace = var.namespace
  values = [file("./utility-files/traefik/values.yaml")]
}
