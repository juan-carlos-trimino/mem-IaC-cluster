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
variable acme_email {
  type = string
}
variable acme_server {
  type = string
}
variable traefik_dns_api_token {
  type = string
}
variable api_token_secret_name {
  type = string
  default = "api-token-secret"
}

resource "kubernetes_secret" "secret" {
  metadata {
    name = var.api_token_secret_name
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  # Plain-text data.
  data = {
    api-token = var.traefik_dns_api_token
  }
  type = "Opaque"
}

# Useful commands for troubleshooting issuing ACME certificates:
# --------------------------------------------------------------
# https://cert-manager.io/docs/faq/acme/#1-troubleshooting-clusterissuers
# $ kubectl get svc,pods -n memories
# $ kubectl get Issuers,ClusterIssuers,Certificates,CertificateRequests,Orders,Challenges -n memories
# $ kubectl get Issuers,ClusterIssuers,Certificates,CertificateRequests,Orders,Challenges --all-namespaces
# $ kubectl describe Issuers,ClusterIssuers,Certificates,CertificateRequests,Orders,Challenges -A
# To describe a specific resource (the resource name can be obtained from the kubectl get command):
# https://letsencrypt.org/docs/challenge-types/#http-01-challenge
# $ kubectl describe Issuer <issuer-name> -n memories
# $ kubectl get ingressroute -A
# $ kubectl get ingress -n memories
# To delete a pending Challenge (https://cert-manager.io/docs/installation/helm/#uninstalling and
# https://cert-manager.io/docs/installation/uninstall/)
# $ kubectl delete Issuer <issuer-name> -n memories
# $ kubectl delete Certificate <certificate-name> -n memories
#
# The ACME Issuer type represents a single account registered with the Automated Certificate
# Management Environment (ACME) Certificate Authority server. When you create a new ACME Issuer,
# cert-manager will generate a private key which is used to identify you with the ACME server.
# https://cert-manager.io/docs/concepts/issuer/
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
      # The ACME protocol is a communications protocol for automating interactions between
      # certificate authorities and their users' web servers, allowing the automated deployment
      # of public key infrastructure at very low cost. It was designed by the Internet Security
      # Research Group (ISRG) for its Let's Encrypt service.
      # https://cert-manager.io/docs/configuration/acme/
      #
      # Use the ACME protocol to issue certificates when you need proof of domain ownership. The
      # ACME HTTP issuer sends an HTTP request to the domains specified in the certificate request.
      # The ACME server expects a certain web page to be published on each domain name requested in
      # the certificate. The cert-manager service publishes the expected web page by creating a
      # temporary pod and ingress. When validation is completed, the temporary pod and ingress are
      # cleaned up. Then, the ACME server issues the certificate.
      # https://cert-manager.io/docs/tutorials/acme/http-validation/
      acme = {
        # Email address used for ACME registration.
        email = var.acme_email
        # The ACME server URL; it will issue the certificates.
        server = var.acme_server
        # preferredChain = "ISRG Root X1"
        # Name of the K8s secret used to store the ACME account private key.
        privateKeySecretRef = {
          name = "le-acme-private-key"
        }
        solvers = [
          # {
          #   selector = {}
          #   http01 = {
          #     ingress = {
          #       # See values.yaml (providers.kubernetesingress.ingressclass).
          #       # class = "traefik-cert-manager"
          #       class = "traefik"
          #       # Valid values are ClusterIP and NodePort.
          #       serviceType = "ClusterIP"
          #       ingressTemplate = {
          #         metadata = {
          #           annotations = {
          #             "traefik.ingress.kubernetes.io/router.tls" = true
          #             "traefik.ingress.kubernetes.io/frontend-entry-points" = "https"
          #           }
          #         }
          #       }
          #     }
          #   }
          # }
          # ACME DNS-01 provider configurations.
          {
            # An empty 'selector' means that this solver matches all domains.
            # selector = {}
            # Only using xxxxxxxxx to solve challenges for trimino.xyz.
            # Alternative options such as 'matchLabels' and 'dnsZones' can be specified as part of
            # a solver's selector as well.
            selector = {
              dnsNames = [
                "trimino.xyz"
              ]
            }
            dns01 = {
              namesilo = {
                tokenSecretRef = {
                  name = var.api_token_secret_name
                  key = "api-token"
                }
              }
            }
          }
        ]
      }
    }
  }
}
