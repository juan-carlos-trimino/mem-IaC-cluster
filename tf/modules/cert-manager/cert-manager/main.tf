/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "namespace" {
  type = string
}
variable "cert_manager_chart_name" {
  type = string
  description = "Cert Manager Helm name."
  default = "cert-manager"
}
variable "cert_manager_chart_repo" {
  type = string
  description = "Cert Manager Helm repository name."
  default = "https://charts.jetstack.io"
}
variable "cert_manager_chart_version" {
  type = string
  description = "Cert Manager Helm version."
  default = "1.7.2"
}

/***
resource "null_resource" "issuer" {
  depends_on = [
    helm_release.cert_manager
  ]
  #
  provisioner "local-exec" {
    command = "kubectl apply -f ./modules/cert-manager/issuers/issuer.yml"
  }
  #
  # provisioner "local-exec" {
    # when = destroy
    # command = "oc delete issuer letsencrypt-staging"
  # }
}

resource "null_resource" "certificate" {
  depends_on = [
    null_resource.issuer
  ]
  #
  provisioner "local-exec" {
    command = "kubectl apply -f ./modules/cert-manager/certificates/traefik-dashboard-cert.yml"
  }
  #
  # provisioner "local-exec" {
    # when = destroy
    # command = "oc delete certificate traefik-dashboard-cert"
  # }
}
***/

# cert-manager adds certificates and certificate issuers as resource types in Kubernetes clusters
# and simplifies the process of obtaining, renewing, and using those certificates.
#
# cert-manager manages non-namespaced resources in the cluster and should only be installed once.
#
# https://cert-manager.io/docs/
#
# Once you've installed cert-manager, you can verify it is deployed correctly by checking the
# cert-manager namespace for running pods:
# $ kubectl get pods --namespace memories
# You should see the cert-manager, cert-manager-cainjector, and cert-manager-webhook pods in a
# Running state.
resource "helm_release" "cert_manager" {
  name = var.cert_manager_chart_name
  repository = var.cert_manager_chart_repo
  chart = var.cert_manager_chart_name
  version = var.cert_manager_chart_version
  namespace = var.namespace
  create_namespace = false
  # values = [file("cert-manager-values.yaml")]
  # To automatically install and manage the CRDs as part of your Helm release, you must add the
  # --set installCRDs=true flag to your Helm installation command.
  set {
    name = "installCRDs"
    value = true
  }
}
