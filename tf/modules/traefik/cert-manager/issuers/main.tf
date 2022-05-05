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
# variable "common_name" {
#   type = string
# }
variable "dns_names" {
  type = list
  default = []
}
variable "self_signed_flag" {
  type = bool
  default = true
}
# variable "acme_email" {
#   type = string
#   default = ""
# }
# variable "acme_server" {
#   type = string
#   default = "https://acme-v02.api.letsencrypt.org/directory"
# }

# Certificate authority.
# https://cert-manager.io/docs/concepts/issuer/
# https://cert-manager.io/docs/faq/acme/#1-troubleshooting-clusterissuers
resource "kubernetes_manifest" "issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Issuer"
    metadata = {
      name = var.issuer_name
      namespace = var.namespace
      labels = {
        app = var.app_name
      }
    }
    spec = {
      # Since a self-signed certificate is being used, a warning will be given when connecting over
      # HTTPS.
      selfSigned = {}
    }
  }
}

# To check the certificate:
# $ kubectl -n memories describe certificate traefik-cert
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
      dnsNames = var.dns_names
      secretName = var.secret_name
      issuerRef = {
        kind = "Issuer"
        name = var.issuer_name
      }
    }
  }
}





/*

# Certificate authority.
# https://cert-manager.io/docs/concepts/issuer/
resource "kubernetes_manifest" "issuer1" {
  count = var.self_signed_flag ? 0 : 1
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Issuer"
    metadata = {
      name = var.issuer_name
      namespace = var.namespace
      labels = {
        app = var.app_name
      }
    }
    spec = {
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
      acme = {
        # Email address used for ACME registration.
        email = var.acme_email
        # The ACME server URL.
        server = var.acme_server
        # Name of a secret used to store the ACME account private key.
        privateKeySecretRef = {
          # Secret resource used to store the account's private key.
          name = var.secret_name
        }
        solvers = [
          {
            http01 = {
              ingress = {
                # See values.yaml (providers.kubernetesingress.ingressclass).
                class = "traefik-cert-manager"
              }
            }
          }
        ]
      }
    }
  }
}

*/






