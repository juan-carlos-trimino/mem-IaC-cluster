/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "namespace" {
  type = string
}

# Certificate authority.
resource "kubernetes_manifest" "issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Issuer"
    metadata = {
      name = "letsencrypt-staging"
      # name = "letsencrypt-prod"
      namespace = var.namespace
    }
    spec = {
      ca = {
        secretName = "traefik-dashboard-cert"
      }
      # The "Automatic Certificate Management Environment" (ACME) protocol is a communications
      # protocol for automating interactions between certificate authorities and their users' web
      # servers, allowing the automated deployment of public key infrastructure at very low cost.
      # It was designed by the Internet Security Research Group (ISRG) for their Let's Encrypt
      # service.
      #
      # See https://cert-manager.io/docs/tutorials/acme/http-validation/
      acme = {
        # Email address used for ACME registration.
        email = "juancarlos.trimino@gmail.com"
        # The ACME server URL.
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        # server = "https://acme-v02.api.letsencrypt.org/directory"
        # Name of a secret used to store the ACME account private key.
        privateKeySecretRef = {
          name = "letsencrypt-staging"
          # name = "letsencrypt-prod"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "traefik-cert-manager"
              }
            }
          }
        ]
      }
    }
  }
}
