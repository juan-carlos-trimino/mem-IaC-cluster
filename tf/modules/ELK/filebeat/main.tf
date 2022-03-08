/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "app_name" {}
variable "image_tag" {}
variable "path_to_files" {}
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
# Certain pods (usually system pods) need to operate in the host's default namespaces, allowing
# them to see and manipulate node-level resources and devices.
# Attaching the hostNetwork permits a pod to access the node’s network adapter allowing a pod to listen to all network traffic for all pods on the node and communicate with other pods on the network namespace.
# Certain pods (usually system pods) need to operate in the host’s default namespaces, allowing them to see and manipulate node-level resources and devices. For example, a pod may need to use the node’s network adapters instead of its own virtual network adapters. This can be achieved by setting the hostNetwork property in the pod spec to true.
# Network interfaces in a pod using the host’s network namespace
# $ kubectl exec pod-with-host-network ifconfig
variable "host_network" {
  default = false
  type = bool
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
# Session affinity and Web Browsers (for LoadBalancer Services)
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
variable "dns_name" {
  default = ""
}
# The ServiceType allows to specify what kind of Service to use: ClusterIP (default),
# NodePort, LoadBalancer, and ExternalName.
variable "service_type" {
  default = "ClusterIP"
}


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
  #   }
  }
  # secret {
  #   name = kubernetes_secret.rabbitmq_secret.metadata[0].name
  # }
}

# Roles define WHAT can be done; role bindings define WHO can do it.
# The distinction between a Role/RoleBinding and a ClusterRole/ClusterRoleBinding is that the Role/
# RoleBinding is a namespaced resource; ClusterRole/ClusterRoleBinding is a cluster-level resource.
# A Role resource defines what actions can be taken on which resources; i.e., which types of HTTP
# requests can be performed on which RESTful resources.
resource "kubernetes_cluster_role" "cluster_role" {
  metadata {
    name = "${var.service_name}-cluster-role"
    labels = {
      app = var.app_name
    }
  }
  rule {
    # The core apiGroup, which has no name - hence the "".
    api_groups = [""]
    verbs = ["get", "watch", "list"]
    # The plural form must be used when specifying resources.
    resources = ["pods", "namespaces"]
  }
}

# Bind the role to the service account.
resource "kubernetes_cluster_role_binding" "cluster_role_binding" {
  metadata {
    name = "${var.service_name}-cluster-role-binding"
    labels = {
      app = var.app_name
    }
  }
  # A RoleBinding always references a single Role, but it can bind the Role to multiple subjects.
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "ClusterRole"
    # This RoleBinding references the Role specified below...
    name = kubernetes_cluster_role.cluster_role.metadata[0].name
  }
  # ... and binds it to the specified ServiceAccount in the specified namespace.
  subject {
    # The default permissions for a ServiceAccount don't allow it to list or modify any resources.
    kind = "ServiceAccount"
    name = kubernetes_service_account.service_account.metadata[0].name
    namespace = kubernetes_service_account.service_account.metadata[0].namespace
  }
}

resource "kubernetes_config_map" "config_files" {
  metadata {
    name = "${var.service_name}-config-files"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  data = {
    "kubernetes.yml" = <<EOF
      - type: docker
        containers.ids:
        - "*"
        processors:
          - add_kubernetes_metadata:
            in_cluster: true
      EOF
    "filebeat.yml" = "${file("${var.path_to_files}/filebeat.yml")}"
  }
}





# $ kubectl get ds -n memories
resource "kubernetes_daemonset" "daemonset" {
  metadata {
    name = var.service_name
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  #
  spec {
    revision_history_limit = var.revision_history_limit
    selector {
      match_labels = {
        pod = var.service_name
      }
    }
    #
    template {
      metadata {
        labels = {
          pod = var.service_name
        }
      }
      #
      spec {
        service_account_name = kubernetes_service_account.service_account.metadata[0].name
        termination_grace_period_seconds = var.termination_grace_period_seconds
        # host_network = var.host_network
        # dns_policy = "ClusterFirstWithHostNet"
        container {
          name = var.service_name
          image = var.image_tag
          image_pull_policy = var.imagePullPolicy
          # security_context {
          #   run_as_user = 0
          #   # If using Red Hat OpenShift, uncomment the line below.
          #   # privileged = true
          # }
          # Docker (CMD)
          args = ["-c", "/etc/filebeat.yml", "-e"]
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
          # By default, Elasticsearch will take the 7 first character of the randomly generated
          # uuid used as the node id. Note that the node id is persisted and does not change when a
          # node restarts and therefore the default node name will also not change.
          # env {
          #   name = "NODE_NAME"
          #   value_from {
          #     field_ref {
          #       # field_path = "metadata.name"
          #       field_path = "spec.nodeName"
          #     }
          #   }
          # }
          # dynamic "env" {
          #   for_each = var.env
          #   content {
          #     name = env.key
          #     value = env.value
          #   }
          # }
          # liveness_probe {
          #   exec {
          #     command = ["rabbitmq-diagnostics", "status", "--erlang-cookie", "$(RABBITMQ_ERLANG_COOKIE)"]
          #   }
          #   initial_delay_seconds = 60
          #   # See https://www.rabbitmq.com/monitoring.html for monitoring frequency recommendations.
          #   period_seconds = 60
          #   timeout_seconds = 15
          #   failure_threshold = 3
          #   success_threshold = 1
          # }
          # readiness_probe {
          #   exec {
          #     command = ["rabbitmq-diagnostics", "status", "--erlang-cookie", "$(RABBITMQ_ERLANG_COOKIE)"]
          #   }
          #   initial_delay_seconds = 20
          #   period_seconds = 60
          #   timeout_seconds = 10
          # }
          # Among the mounted filesystems that Filebeat will have access to, we are specifying /var/lib/docker/containers. Notice that the volume type of this path is hostPath (line 120), which means that Filebeat will have access to this path on the node rather than the container. Kubernetes uses this path on the node to write data about the containers, additionally, any STDOUT or STDERR coming from the containers running on the node is directed to this path in JSON format (the standard output and standard error data is still viewable through the kubectl logs command, but a copy is kept at that path).
          volume_mount {
            name = "config"
            mount_path = "/etc/filebeat.yml"
            sub_path = "filebeat.yml"
            read_only = true
          }
          volume_mount {
            name = "prospectors"
            mount_path = "/usr/share/filebeat/prospectors.d"
            read_only = true
          }
          volume_mount {
            name = "data"
            mount_path = "/usr/share/filebeat/data"
            read_only = false
          }
          volume_mount {
            name = "varlibdockercontainers"
           mount_path = "/var/lib/docker/containers"
           read_only = false
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.config_files.metadata[0].name
            default_mode = "0600"
            items {
              key = "filebeat.yml"
              path = "filebeat.yml"  # File name.
            }
          }
        }
        volume {
          name = "prospectors"
          config_map {
            name = kubernetes_config_map.config_files.metadata[0].name
            default_mode = "0600"
            items {
              key = "kubernetes.yml"
              path = "kubernetes.yml"  # File name.
            }
          }
        }
        volume {
          name = "data"
          empty_dir {}
        }
        volume {
          name = "varlibdockercontainers"
          host_path {
            path = "/var/lib/docker/containers"
          }
        }
      }
    }
  }
}
