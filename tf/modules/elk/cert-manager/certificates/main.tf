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
variable issuer_name {
  type = string
}
variable certificate_name {
  type = string
}
variable dns_names {
  type = list
  default = []
}
variable secret_name {
  type = string
}

# Create a Let's Encrypt TLS Certificate for the domain and inject it into K8s secrets.
resource "kubernetes_manifest" "certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Certificate"
    metadata = {
      name = var.certificate_name
      namespace = var.namespace
      labels = {
        app = var.app_name
      }
    }
    spec = {
      isCA = null
      dnsNames = var.dns_names  # Add subdomains.
      duration = "2160h0m0s"  # 90 days.
      renewBefore = "720h0m0s"  # 30 days.
      # The name of the secret resource that will be automatically created and managed by this
      # Certificate resource. It will be populated with a private key and certificate, signed by
      # the denoted issuer.
      secretName = var.secret_name
      # The Certificate will be issued using the issuer named 'var.issuer_name' in the
      # 'var.namespace' namespace (the same namespace as the Certificate resource).
      issuerRef = {
        kind = "Issuer"
        name = var.issuer_name
        # This is optional since cert-manager will default to this value; however, if you are using
        # an external issuer, change this to that issuer group.
        group = "cert-manager.io"
      }
    }
  }
}
