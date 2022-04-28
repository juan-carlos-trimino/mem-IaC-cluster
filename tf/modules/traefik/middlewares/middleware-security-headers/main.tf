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
variable "service_name" {
  type = string
}

resource "kubernetes_manifest" "middleware" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind = "Middleware"
    metadata = {
      name = "${var.service_name}"
      namespace = var.namespace
      labels = {
        app = var.app_name
      }
    }
    # https://doc.traefik.io/traefik/middlewares/http/headers/#using-security-headers
    spec = {
      headers = {
        frameDeny = true
        sslRedirect = true
        browserXssFilter = true
        contentTypeNosniff = true
        stsIncludeSubdomains = true
        stsPreload = true
        stsSeconds = 31536000  # 365 days
      }
    }
  }
}
