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
# variable common_name {
#   type = string
# }
variable dns_names {
  type = list
  default = []
}
variable secret_name {
  type = string
}

# Create a Let's Encrypt TLS Certificate for the domain and inject it into K8s secrets.
# To check the certificate:
# $ kubectl -n memories describe certificate le-dashboard-cert
# $ kubectl -n memories delete certificate le-dashboard-cert
# $ kubectl -n memories describe certificate le-cert
# $ kubectl -n memories delete certificate le-cert
resource "kubernetes_manifest" "certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Certificate"
    metadata = {
      name = var.certificate_name
      namespace = var.namespace
      labels = {
        app = var.app_name
        use-http01-solver = true
      }
    }
    spec = {
      isCA = true
      privateKey = {
        # Setting the rotationPolicy to Always won't rotate the private key immediately. In order
        # to rotate the private key, the certificate objects must be reissued.
        rotationPolicy = "Always"
        size = 4096
        algorithm = "RSA"
        encoding = "PKCS1"
      }
      # The certificate commonName and dnsNames are challenged by the ACME server. The certificate
      # manager service automatically creates a pod and ingress rules to resolve the challenges.
      # (The use of the common name field has been deprecated since 2000 and is discouraged from
      # being used.)
      # commonName = var.common_name  # This is the main DNS name for the cert.
      dnsNames = var.dns_names  # Add subdomains.
      # The default duration for all certificates is 90 days and the default renewal windows is 30
      # days. This means that certificates are considered valid for 3 months and renewal will be
      # attempted within 1 month of expiration.
      # duration = "360h"  # 15 days.
      # renewBefore = "24h"
      # The signed certificate will be stored in a Secret resource named 'var.secret_name' in the
      # same namespace as the Certificate once the issuer has successfully issued the requested
      # certificate.
      secretName = var.secret_name
      # The Certificate will be issued using the issuer named 'var.issuer_name' in the
      # 'var.namespace' namespace (the same namespace as the Certificate resource).
      issuerRef = {
        kind = "Issuer"
        name = var.issuer_name
      }
    }
  }
}
