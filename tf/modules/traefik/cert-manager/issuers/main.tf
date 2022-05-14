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
variable "acme_email" {
  type = string
}
variable "acme_server" {
  type = string
}
variable "certificate_name" {
  type = string
}
variable "common_name" {
  type = string
}
variable "dns_names" {
  type = list
  default = []
}
variable "secret_name" {
  type = string
}

# Useful commands for troubleshooting issuing ACME certificates:
# --------------------------------------------------------------
# $ kubectl get svc,pods -n memories
# $ kubectl get Issuers,ClusterIssuers,Certificates,CertificateRequests,Orders,Challenges -n memories
# $ kubectl get Issuers,ClusterIssuers,Certificates,CertificateRequests,Orders,Challenges --all-namespaces
# $ kubectl describe Issuers,ClusterIssuers,Certificates,CertificateRequests,Orders,Challenges -A
# To describe a specific resource (the resource name can be obtained from the kubectl get command):
# For more information on Challenge resources, go to https://letsencrypt.org/docs/challenge-types/#http-01-challenge
# $ kubectl describe Issuer <issuer-name> -n memories
# $ kubectl get ingressroute -A
# $ kubectl get ingress -n memories
# To delete a pending Challenge (https://cert-manager.io/docs/installation/helm/#uninstalling)
# https://cert-manager.io/docs/installation/uninstall/
# $ kubectl delete Issuer <issuer-name> -n memories
# $ kubectl delete Certificate <certificate-name> -n memories
#
# cert-manager adds certificates and certificate issuers as resource types in Kubernetes clusters,
# and it simplifies the process of obtaining, renewing and using those certificates.
# https://cert-manager.io/docs/
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
      # The "Automatic Certificate Management Environment" (ACME) protocol is a communications
      # protocol for automating interactions between certificate authorities and their users' web
      # servers, allowing the automated deployment of public key infrastructure at very low cost.
      # It was designed by the Internet Security Research Group (ISRG) for their Let's Encrypt
      # service.
      #
      # Use the ACME protocol to issue certificates when you need proof of domain ownership. The
      # ACME HTTP issuer sends an HTTP request to the domains specified in the certificate request.
      # The ACME server expects a certain web page to be published on each domain name requested in
      # the certificate. The cert-manager service publishes the expected web page by creating a
      # temporary pod and ingress. When validation is completed, the temporary pod and ingress are
      # cleaned up. Then, the ACME server issues the certificate.
      #
      # See https://cert-manager.io/docs/tutorials/acme/http-validation/
      acme = {
        # Email address used for ACME registration.
        email = var.acme_email
        # The ACME server URL; it will issue the certificates.
        server = var.acme_server
        # Name of the K8s secret used to store the ACME account private key.
        privateKeySecretRef = {
          name = "le-private-key"
        }
        solvers = [
          {
            selector = {}
            http01 = {
              ingress = {
                # See values.yaml (providers.kubernetesingress.ingressclass).
                # class = "traefik-cert-manager"
                class = "traefik"
              }
            }
          }
        ]
      }
    }
  }
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
      # The certificate commonName and dnsNames are challenged by the ACME server. The certificate
      # manager service automatically creates a pod and ingress rules to resolve the challenges.
      commonName = var.common_name
      dnsNames = var.dns_names
      # The default duration for all certificates is 90 days and the default renewal windows is 30
      # days. This means that certificates are considered valid for 3 months and renewal will be
      # attempted within 1 month of expiration.
      # duration = "360h"  # 15 days.
      # renewBefore = "24h"
      # It instructs cert-manager to store the certificate in the secretName.
      secretName = var.secret_name
      issuerRef = {
        kind = "Issuer"
        name = var.issuer_name
      }
    }
  }
}
