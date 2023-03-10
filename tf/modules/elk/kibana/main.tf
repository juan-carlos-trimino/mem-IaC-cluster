/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable app_name {
  type = string
}
variable image_tag {
  type = string
}
variable namespace {
  default = "default"
  type = string
}
# Be aware that the default imagePullPolicy depends on the image tag. If a container refers to the
# latest tag (either explicitly or by not specifying the tag at all), imagePullPolicy defaults to
# Always, but if the container refers to any other tag, the policy defaults to IfNotPresent.
#
# When using a tag other that latest, the imagePullPolicy property must be set if changes are made
# to an image without changing the tag. Better yet, always push changes to an image under a new
# tag.
variable image_pull_policy {
  default = "Always"
  type = string
}
variable env {
  default = {}
  type = map
}
variable qos_requests_cpu {
  default = ""
  type = string
}
variable qos_requests_memory {
  default = ""
  type = string
}
variable qos_limits_cpu {
  default = "0"
  type = string
}
variable qos_limits_memory {
  default = "0"
  type = string
}
variable replicas {
  default = 1
  type = number
}
variable revision_history_limit {
  default = 2
  type = number
}
# The termination grace period defaults to 30, which means the pod's containers will be given 30
# seconds to terminate gracefully before they're killed forcibly.
variable termination_grace_period_seconds {
  default = 30
  type = number
}
variable service_name {
  type = string
}
variable service_session_affinity {
  default = "None"
  type = string
}
variable service_port {
  type = number
}
variable service_target_port {
  type = number
}
# The ServiceType allows to specify what kind of Service to use: ClusterIP (default),
# NodePort, LoadBalancer, and ExternalName.
variable service_type {
  default = "ClusterIP"
  type = string
}

/***
Define local variables.
***/
locals {
  pod_selector_label = "rs-${var.service_name}"
  svc_selector_label = "svc-${var.service_name}"
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
  #
  spec {
    replicas = var.replicas
    revision_history_limit = var.revision_history_limit
    # The label selector determines the pods the ReplicaSet manages.
    selector {
      match_labels = {
        # It must match the labels in the Pod template.
        pod_selector_lbl = local.pod_selector_label
      }
    }
    # The Pod template.
    template {
      metadata {
        # Labels attach to the Pod.
        # The pod-template-hash label is added by the Deployment controller to every ReplicaSet
        # that a Deployment creates or adopts.
        labels = {
          app = var.app_name
          # It must match the label selector of the ReplicaSet.
          pod_selector_lbl = local.pod_selector_label
          # It must match the label selector of the Service.
          svc_selector_lbl = local.svc_selector_label
        }
      }
      #
      spec {
        termination_grace_period_seconds = var.termination_grace_period_seconds
        container {
          name = var.service_name
          image = var.image_tag
          image_pull_policy = var.image_pull_policy
          security_context {
            capabilities {
              drop = ["ALL"]
            }
            run_as_non_root = true
            run_as_user = 1000
            run_as_group = 1000
          }
          # Specifying ports in the pod definition is purely informational. Omitting them has no
          # effect on whether clients can connect to the pod through the port or not. If the
          # container is accepting connections through a port bound to the 0.0.0.0 address, other
          # pods can always connect to it, even if the port isn't listed in the pod spec
          # explicitly. Nonetheless, it is good practice to define the ports explicitly so that
          # everyone using the cluster can quickly see what ports each pod exposes.
          port {
            name = "kibana"
            container_port = var.service_target_port  # The port the app is listening.
            protocol = "TCP"
          }
          resources {
            requests = {
              # If a Container specifies its own memory limit, but does not specify a memory
              # request, Kubernetes automatically assigns a memory request that matches the limit.
              # Similarly, if a Container specifies its own CPU limit, but does not specify a CPU
              # request, Kubernetes automatically assigns a CPU request that matches the limit.
              cpu = var.qos_requests_cpu == "" ? var.qos_limits_cpu : var.qos_requests_cpu
              memory = var.qos_requests_memory == "" ? var.qos_limits_memory : var.qos_requests_memory
            }
            limits = {
              cpu = var.qos_limits_cpu
              memory = var.qos_limits_memory
            }
          }
          # A human-readable display name that identifies this Kibana instance.
          env {
            name = "server.name"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          dynamic "env" {
            for_each = var.env
            content {
              name = env.key
              value = env.value
            }
          }
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
      svc_selector_lbl = local.svc_selector_label
    }
    session_affinity = var.service_session_affinity
    port {
      name = "kibana"
      port = var.service_port  # Service port.
      target_port = var.service_target_port  # Pod port.
      protocol = "TCP"
    }
    type = var.service_type
  }
}
