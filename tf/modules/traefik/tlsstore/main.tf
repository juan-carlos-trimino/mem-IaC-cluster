/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable app_name {
  type = string
}
variable namespace {
  type = string
}
variable secret_name {
  type = string
}
variable service_name {
  type = string
}

# Traefik currently only uses the TLS Store named "default"
# (https://doc.traefik.io/traefik/https/tls/#certificates-stores). This means that if you have two
# stores that are named default in different Kubernetes namespaces, they may be randomly chosen.
# For the time being, please only configure one TLSSTore named default.
#
# If Traefik is handling all requests for a domain, you may want to substitute the default Traefik
# certificate with another certificate, such as a wildcard certificate for the entire domain. To
# accomplish the substitution, create a TLSStore resource and set the defaultCertificate key to the
# secret that contains the certificate.
resource "kubernetes_manifest" "tlsstore" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind = "TLSStore"
    metadata = {
      name = var.service_name
      namespace = var.namespace
      labels = {
        app = var.app_name
      }
    }
    spec = {
      defaultCertificate = {
        secretName = var.secret_name
      }
    }
  }
}
