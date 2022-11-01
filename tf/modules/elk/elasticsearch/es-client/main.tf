/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable app_name {}
variable image_tag {}
variable namespace {
  default = "default"
}
variable imagePullPolicy {
  default = "Always"
}
variable env {
  default = {}
  type = map
}
variable qos_requests_cpu {
  default = ""
}
variable qos_requests_memory {
  default = ""
}
variable qos_limits_cpu {
  default = "0"
}
variable qos_limits_memory {
  default = "0"
}
variable replicas {
  default = 1
  type = number
}
variable revision_history_limit {
  default = 2
  type = number
}
variable termination_grace_period_seconds {
  default = 30
  type = number
}
variable service_name {
  default = ""
}
variable service_session_affinity {
  default = "None"
}
variable http_service_port {
  type = number
}
variable http_service_target_port {
  type = number
}
variable service_type {
  default = "ClusterIP"
}

/***
Define local variables.
***/
locals {
  rs_label = "rs-${var.service_name}"
  svc_label = "svc-${var.service_name}"
  es_label = "es-cluster"
}

# resource "kubernetes_service_account" "service_account" {
#   metadata {
#     name = "${var.service_name}-service-account"
#     namespace = var.namespace
#     labels = {
#       app = var.app_name
#     }
#     # annotations = {
#       # "kubernetes.io/enforce-mountable-secrets" = true
#   #   }
#   }
#   # secret {
#   #   name = kubernetes_secret.rabbitmq_secret.metadata[0].name
#   # }
# }

# resource "kubernetes_role" "role" {
#   metadata {
#     name = "${var.service_name}-role"
#     namespace = var.namespace
#     labels = {
#       app = var.app_name
#     }
#   }
#   rule {
#     # Resources in the core apiGroup, which has no name - hence the "".
#     api_groups = [""]
#     verbs = ["get", "watch", "list"]
#     # The plural form must be used when specifying resources.
#     resources = ["endpoints", "services", "namespaces"]
#   }
#   rule {
#     api_groups = ["security.openshift.io"]
#     verbs = ["use"]
#     resources = ["securitycontextconstraints"]
#     resource_names = ["mem-elasticsearch-scc"]
#   }
# }

# resource "kubernetes_role_binding" "role_binding" {
#   metadata {
#     name = "${var.service_name}-role-binding"
#     namespace = var.namespace
#     labels = {
#       app = var.app_name
#     }
#   }
#   # A RoleBinding always references a single Role, but it can bind the Role to multiple subjects.
#   role_ref {
#     api_group = "rbac.authorization.k8s.io"
#     kind = "Role"
#     # This RoleBinding references the Role specified below...
#     name = kubernetes_role.role.metadata[0].name
#   }
#   # ... and binds it to the specified ServiceAccount in the specified namespace.
#   subject {
#     # The default permissions for a ServiceAccount don't allow it to list or modify any resources.
#     kind = "ServiceAccount"
#     name = kubernetes_service_account.service_account.metadata[0].name
#     namespace = kubernetes_service_account.service_account.metadata[0].namespace
#   }
# }

resource "kubernetes_deployment" "deployment" {
  metadata {
    name = var.service_name
    namespace = var.namespace
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
        rs_lbl = local.rs_label
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
          rs_lbl = local.rs_label
          # It must match the label selector of the Service.
          svc_lbl = local.svc_label
          es_lbl = local.es_label
          es_role_lbl = "es-client"
        }
      }
      # The Pod template's specification.
      spec {
        termination_grace_period_seconds = var.termination_grace_period_seconds
        # service_account_name = kubernetes_service_account.service_account.metadata[0].name
        affinity {
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              label_selector {
                match_expressions {
                  key = "es_lbl"
                  operator = "In"
                  values = ["${local.es_label}"]
                }
              }
              topology_key = "kubernetes.io/hostname"
            }
          }
        }
        # Elasticsearch requires vm.max_map_count to be at least 262144. If the OS already sets up
        # this number to a higher value, feel free to remove the init container.
        # init_container {
        #   name = "increase-vm-max-map-count"
        #   image = "busybox:1.34.1"
        #   image_pull_policy = "IfNotPresent"
        #   # Docker (ENTRYPOINT)
        #   command = ["sysctl", "-w", "vm.max_map_count=262144"]
        #   security_context {
        #     # run_as_group = 0
        #     # run_as_non_root = false
        #     # run_as_user = 0
        #     read_only_root_filesystem = true
        #     privileged = true
        #   }
        # }
        # Increase the max number of open file descriptors.
        # init_container {
        #   name = "increase-fd-ulimit"
        #   image = "busybox:1.34.1"
        #   image_pull_policy = "IfNotPresent"
        #   # Docker (ENTRYPOINT)
        #   command = ["/bin/sh", "-c", "ulimit -n 65536"]
        #   security_context {
        #     # run_as_group = 0
        #     # run_as_non_root = false
        #     # run_as_user = 0
        #     read_only_root_filesystem = true
        #     privileged = true
        #   }
        # }
        container {
          name = var.service_name
          image = var.image_tag
          image_pull_policy = var.imagePullPolicy
          security_context {
            capabilities {
              drop = ["ALL"]
            }
            run_as_group = 1000
            run_as_non_root = true
            run_as_user = 1000
            read_only_root_filesystem = false
            privileged = false
          }
          port {
            name = "http"
            container_port = var.http_service_target_port  # The port the app is listening.
            protocol = "TCP"
          }
          resources {
            requests = {
              cpu = var.qos_requests_cpu == "" ? var.qos_limits_cpu : var.qos_requests_cpu
              memory = (
                var.qos_requests_memory == "" ? var.qos_limits_memory : var.qos_requests_memory
              )
            }
            limits = {
              cpu = var.qos_limits_cpu
              memory = var.qos_limits_memory
            }
          }
          env {
            name = "node.name"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          env {
            name = "network.host"
            value_from {
              field_ref {
                field_path = "status.podIP"
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
          volume_mount {
            name = "es-storage"
            mount_path = "/es-data"
          }
        }
        volume {
          name = "es-storage"
          empty_dir {
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
      svc_lbl = local.svc_label
    }
    session_affinity = var.service_session_affinity
    port {
      name = "http"
      port = var.http_service_port  # Service port.
      target_port = var.http_service_target_port  # Pod port.
      protocol = "TCP"
    }
    type = var.service_type
  }
}
