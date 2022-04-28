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
variable "issuer_name" {
  type = string
}
variable "certificate_name" {
  type = string
}
variable "secret_name" {
  type = string
}
variable "dns_names" {
  type = list
  default = []
}

# Certificate authority.
# Create a certificate with an issuer.
# https://cert-manager.io/docs/concepts/issuer/
resource "kubernetes_manifest" "issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Issuer"
    metadata = {
      name = var.issuer_name
      # name = "letsencrypt-staging"
      # name = "letsencrypt-prod"
      namespace = var.namespace
      labels = {
        app = var.app_name
      }
    }
    spec = {
      # Since a self-signed certificate is being used, a warning will be given when connecting over
      # HTTPS.
      selfSigned = {}
      # ca = {
      #   secretName = "traefik-dashboard-cert"
      # }
      # The "Automatic Certificate Management Environment" (ACME) protocol is a communications
      # protocol for automating interactions between certificate authorities and their users' web
      # servers, allowing the automated deployment of public key infrastructure at very low cost.
      # It was designed by the Internet Security Research Group (ISRG) for their Let's Encrypt
      # service.
      #
      # See https://cert-manager.io/docs/tutorials/acme/http-validation/
      # acme = {
      #   # Email address used for ACME registration.
      #   email = "juancarlos@trimino.com"
      #   # The ACME server URL.
      #   server = "https://acme-staging-v02.api.letsencrypt.org/directory"
      #   # server = "https://acme-v02.api.letsencrypt.org/directory"
      #   # Name of a secret used to store the ACME account private key.
      #   privateKeySecretRef = {
      #     name = "letsencrypt-staging"
      #     # name = "letsencrypt-prod"
      #   }
      #   solvers = [
      #     {
      #       http01 = {
      #         ingress = {
      #           class = "traefik-cert-manager"
      #         }
      #       }
      #     }
      #   ]
      # }
    }
  }
}

resource "kubernetes_manifest" "certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Certificate"
    metadata = {
      name = var.certificate_name
      # name = "letsencrypt-staging"
      # name = "letsencrypt-prod"
      namespace = var.namespace
      labels = {
        app = var.app_name
      }
    }
    spec = {
      dnsNames = var.dns_names
      secretName = var.secret_name
      issuerRef = {
        kind = "Issuer"
        name = var.issuer_name
      }
    }
  }
}
