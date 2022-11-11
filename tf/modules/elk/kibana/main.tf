/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "app_name" {}
variable "image_tag" {}
variable "namespace" {
  default = "default"
}
# Be aware that the default imagePullPolicy depends on the image tag. If a container refers to the
# latest tag (either explicitly or by not specifying the tag at all), imagePullPolicy defaults to
# Always, but if the container refers to any other tag, the policy defaults to IfNotPresent.
#
# When using a tag other that latest, the imagePullPolicy property must be set if changes are made
# to an image without changing the tag. Better yet, always push changes to an image under a new
# tag.
variable "imagePullPolicy" {
  default = "Always"
}
variable "env" {
  default = {}
  type = map
}
variable "qos_requests_cpu" {
  default = ""
}
variable "qos_requests_memory" {
  default = ""
}
variable "qos_limits_cpu" {
  default = "0"
}
variable "qos_limits_memory" {
  default = "0"
}
variable "replicas" {
  default = 1
  type = number
}
variable "revision_history_limit" {
  default = 2
  type = number
}
# The termination grace period defaults to 30, which means the pod's containers will be given 30
# seconds to terminate gracefully before they're killed forcibly.
variable "termination_grace_period_seconds" {
  default = 30
  type = number
}
variable "service_name" {
  default = ""
}
# The service normally forwards each connection to a randomly selected backing pod. To
# ensure that connections from a particular client are passed to the same Pod each time,
# set the service's sessionAffinity property to ClientIP instead of None (default).
#
# xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxSession affinity and Web Browsers (for LoadBalancer Services)
# Since the service is now exposed externally, accessing it with a web browser will hit
# the same pod every time. If the sessionAffinity is set to None, then why? The browser
# is using keep-alive connections and sends all its requests through a single connection.
# Services work at the connection level, and when a connection to a service is initially
# open, a random pod is selected and then all network packets belonging to that connection
# are sent to that single pod. Even with the sessionAffinity set to None, the same pod will
# always get hit (until the connection is closed).
variable "service_session_affinity" {
  default = "None"
}
variable "service_port" {
  type = number
}
variable "service_target_port" {
  type = number
}
# The ServiceType allows to specify what kind of Service to use: ClusterIP (default),
# NodePort, LoadBalancer, and ExternalName.
variable "service_type" {
  default = "ClusterIP"
}

resource "kubernetes_deployment" "deployment" {
  metadata {
    name = var.service_name
    namespace = var.namespace
    labels = {
      app = var.app_name
      pod = var.service_name
    }
  }
  #
  spec {
    replicas = var.replicas
    revision_history_limit = var.revision_history_limit
    selector {
      match_labels = {
        pod = var.service_name
      }
    }
    template {
      metadata {
        labels = {
          pod = var.service_name
        }
      }
      #
      spec {
        termination_grace_period_seconds = var.termination_grace_period_seconds
        container {
          name = var.service_name
          image = var.image_tag
          image_pull_policy = var.imagePullPolicy
          # command = ["/bin/sh", "-c", "/usr/share/kibana/bin/kibana-plugin remove x-pack && /usr/local/bin/kibana-docker"]
          # security_context {
          #   read_only_root_filesystem = false
          # }
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
          # # A human-readable display name that identifies this Kibana instance.
          # env {
          #   name = "server.name"
          #   value_from {
          #     field_ref {
          #       field_path = "metadata.name"
          #     }
          #   }
          # }
          # # By default, Elasticsearch only binds to loopback addresses such as 127.0.0.1 and [::1].
          # env {
          #   name = "network.host"
          #   value_from {
          #     field_ref {
          #       field_path = "status.podIP"
          #     }
          #   }
          # }
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
    selector = {
      pod = kubernetes_deployment.deployment.metadata[0].labels.pod
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
