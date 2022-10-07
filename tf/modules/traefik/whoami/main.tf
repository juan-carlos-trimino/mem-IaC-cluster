/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "app_name" {}
variable "app_version" {}
variable "namespace" {
  default = "default"
}
variable "replicas" {
  default = 1
  type = number
}
# Be aware that the default imagePullPolicy depends on the image tag. If a container refers to the
# latest tag (either explicitly or by not specifying the tag at all), imagePullPolicy defaults to
# Always, but if the container refers to any other tag, the policy defaults to IfNotPresent.
#
# When using a tag other than latest, the imagePullPolicy property must be set if changes are made
# to an image without changing the tag. Better yet, always push changes to an image under a new
# tag.
variable "imagePullPolicy" {
  default = "Always"
}
variable "service_name" {
  default = ""
}
# The ServiceType allows to specify what kind of Service to use: ClusterIP (default),
# NodePort, LoadBalancer, and ExternalName.
variable "service_type" {
  default = "ClusterIP"
}
variable "service_port" {
  type = number
  default = 80
}
variable "service_target_port" {
  type = number
  default = 8080
}

/***
Define local variables.
***/
locals {
  rs_label = "rs-${var.service_name}"
  svc_label = "svc-${var.service_name}"
  image_tag = "containous/whoami:latest"
}

resource "kubernetes_service_account" "service_account" {
  metadata {
    name = "${var.service_name}-service-account"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
}

resource "kubernetes_role" "role" {
  metadata {
    name = "${var.service_name}-role"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  rule {
    api_groups = ["security.openshift.io"]
    verbs = ["use"]
    resources = ["securitycontextconstraints"]
    resource_names = ["mem-traefik-scc"]
  }
}

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

resource "kubernetes_deployment" "deployment" {
  metadata {
    name = var.service_name
    namespace = var.namespace
    # Labels attach to the Deployment.
    labels = {
      app = var.app_name
    }
  }
  # The Deployment's specification.
  spec {
    # The desired number of pods that should be running.
    replicas = var.replicas
    # The label selector determines the pods the ReplicaSet manages.
    selector {
      match_labels = {
        # It must match the labels in the Pod template.
        rs_lbl = local.rs_label
      }
    }
    # The Pod template.
    template {
      metadata {
        labels = {
          app = var.app_name
          # It must match the label selector of the ReplicaSet.
          rs_lbl = local.rs_label
          # It must match the label selector of the Service.
          svc_lbl = local.svc_label
        }
      }
      # The Pod template's specification.
      spec {
        service_account_name = kubernetes_service_account.service_account.metadata[0].name
        container {
          name = var.service_name
          image = local.image_tag
          image_pull_policy = var.imagePullPolicy
          # Specifying ports in the pod definition is purely informational. Omitting them has no
          # effect on whether clients can connect to the pod through the port or not.
          port {
            container_port = var.service_target_port  # The port the app is listening.
            protocol = "TCP"
          }
          security_context {
            read_only_root_filesystem = true
            allow_privilege_escalation = false
            capabilities {
              add = ["NET_BIND_SERVICE"]
            }
          }
          # env {
          #   name = "WHOAMI_PORT_NUMBER"
          #   value = var.service_target_port
          # }
        }
      }
    }
  }
}

# Declare a K8s service to create a DNS record to make the microservice accessible within the
# cluster.
resource "kubernetes_service" "service" {
  metadata {
    name = var.service_name
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  #
  spec {
    # The label selector determines which pods belong to the service.
    selector = {
      svc_lbl = local.svc_label
    }
    port {
      port = var.service_port  # Service port.
      target_port = var.service_target_port  # Pod port.
    }
    type = var.service_type
  }
}
