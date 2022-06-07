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

# TLS Options: https://doc.traefik.io/traefik/https/tls/#tls-options
resource "kubernetes_manifest" "tlsoption" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind = "TLSOption"
    metadata = {
      name = var.service_name
      namespace = var.namespace
      labels = {
        app = var.app_name
      }
    }
    spec = {
      minVersion = "VersionTLS12"
      cipherSuites = [
        "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256",
        "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
        "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
        "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305",
        "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
        "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305",
        "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305",
        "TLS_AES_256_GCM_SHA384",
        "TLS_AES_128_GCM_SHA256",
        "TLS_CHACHA20_POLY1305_SHA256",
        "TLS_FALLBACK_SCSV"
      ]
      curvePreferences = [
        "CurveP521",
        "CurveP384"
      ]
      sniStrict = true
    }
  }
}
