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
variable "ingress_controller_chart_name" {
  type = string
  description = "Ingress Controller Helm chart name."
  default = "traefik"
}
variable "ingress_controller_chart_repo" {
  type = string
  description = "Using the official Traefik helm chart (Ingress Controller)."
  default = "https://helm.traefik.io/traefik"
}
variable "ingress_controller_chart_version" {
  type = string
  description = "Ingress Controller Helm repository version."
  default = "10.9.1"
}

###################################################################################################
# To use the service account below:                                                               #
# (1) In this file, uncomment the lines from /***SA to SA***/.                                    #
# (2) In the file "mem-traefik-scc.yaml", find section "users:" and change it from:               #
#     users: [                                                                                    #
#       # system:serviceaccount:memories:mem-traefik-service-account                              #
#     ]                                                                                           #
#                                                                                                 #
#     to                                                                                          #
#                                                                                                 #
#     users: [                                                                                    #
#       system:serviceaccount:memories:mem-traefik-service-account                                #
#     ]                                                                                           #
# (3) In the file "values.yaml", find section "serviceAccount:" and change it from:               #
#     serviceAccount:                                                                             #
#       # name: "mem-traefik-service-account"                                                     #
#       name: ""                                                                                  #
#                                                                                                 #
#     to                                                                                          #
#                                                                                                 #
#     serviceAccount:                                                                             #
#       name: "mem-traefik-service-account"                                                       #
#       # name: ""                                                                                #
###################################################################################################
resource "null_resource" "scc-traefik" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "oc apply -f ./utility-files/traefik/mem-traefik-scc.yaml"
  }
  #
  provisioner "local-exec" {
    when = destroy
    command = "oc delete scc mem-traefik-scc"
  }
}

/***SA
# A ServiceAccount is used by an application running inside a pod to authenticate itself with the
# API server. A default ServiceAccount is automatically created for each namespace; each pod is
# associated with exactly one ServiceAccount, but multiple pods can use the same ServiceAccount. A
# pod can only use a ServiceAccount from the same namespace.
#
# For cluster security, let's constrain the cluster metadata this pod may read.
resource "kubernetes_service_account" "service_account" {
  metadata {
    name = "${var.service_name}-service-account"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
    # annotations = {
      # "kubernetes.io/enforce-mountable-secrets" = true
    # }
  }
  # secret {
  #   name = kubernetes_secret.secret.metadata[0].name
  # }
}

# Roles define WHAT can be done; role bindings define WHO can do it.
# The distinction between a Role/RoleBinding and a ClusterRole/ClusterRoleBinding is that the Role/
# RoleBinding is a namespaced resource; ClusterRole/ClusterRoleBinding is a cluster-level resource.
# A Role resource defines what actions can be taken on which resources; i.e., which types of HTTP
# requests can be performed on which RESTful resources.
resource "kubernetes_role" "role" {
  metadata {
    name = "${var.service_name}-role"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  rule {
    # Resources in the core apiGroup, which has no name - hence the "".
    api_groups = [""]
    verbs = ["get", "watch", "list"]
    # The plural form must be used when specifying resources.
    resources = ["services", "endpoints", "secrets"]
  }
  rule {
    api_groups = ["traefik.containo.us/v1alpha1"]
    verbs = ["get", "watch", "list"]
    resources = ["ingressroutes"]
  }
  rule {
    api_groups = ["security.openshift.io"]
    verbs = ["use"]
    resources = ["securitycontextconstraints"]
    resource_names = ["mem-traefik-scc"]
  }
}

# Bind the role to the service account.
resource "kubernetes_role_binding" "role_binding" {
  metadata {
    name = "${var.service_name}-role-binding"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  # A RoleBinding always references a single Role, but it can bind the Role to multiple subjects.
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "Role"
    # This RoleBinding references the Role specified below...
    name = kubernetes_role.role.metadata[0].name
  }
  # ... and binds it to the specified ServiceAccount in the specified namespace.
  subject {
    # The default permissions for a ServiceAccount don't allow it to list or modify any resources.
    kind = "ServiceAccount"
    name = kubernetes_service_account.service_account.metadata[0].name
    namespace = kubernetes_service_account.service_account.metadata[0].namespace
  }
}
SA***/

# Traefik is a Cloud Native Edge Router that will work as an ingress controller to a Kubernetes
# cluster. It will be responsible to make sure that when the traffic from a web application hits
# the Kubernetes cluster, it will go to the right Service. Also, it makes it very easy to assign
# an SSL/TLS certificate to the web application.
#
# Notes:
# 1. To watch the traefik's logs:
#    $ kubectl logs -n memories -l app.kubernetes.io/name=traefik -f
# 2. Traefik supports the ACME protocol used by Let's Encrypt.
# 3. By default, the chart will deploy Traefik in LoadBalancer mode.
# 4. EntryPoints are the network entry points into Traefik. They define the port which will receive
#    the packets, and whether to listen for TCP or UDP. The Traefik Helm chart deployment creates
#    the following entrypoints:
#    * web: It is used for all HTTP requests. The Kubernetes LoadBalancer service maps port 80 to
#           the web entrypoint.
#    * websecure: It is used for all HTTPS requests. The Kubernetes LoadBalancer service maps port
#                 443 to the websecure entrypoint.
#    * traefik: Kubernetes uses the Traefik Proxy entrypoint for pod liveliness check. The Traefik
#               dashboard and API are available on the Traefik entrypoint.
#    Applications are configured either on the web or the websecure entrypoints.
#    web - port 8000 (exposed as port 80)
#    websecure - port 8443 (exposed as port 443)
#    traefik - port 9000 (not exposed)
#    metrics - port 9100 (not exposed)
resource "helm_release" "ingress_controller_traefik" {
  name = var.ingress_controller_chart_name
  chart = var.ingress_controller_chart_name
  repository = var.ingress_controller_chart_repo
  version = var.ingress_controller_chart_version
  namespace = var.namespace
  values = [file("./utility-files/traefik/values.yaml")]
  timeout = 150
}
