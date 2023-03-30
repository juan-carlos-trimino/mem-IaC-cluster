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
variable image_pull_policy {
  default = "Always"
  type = string
}
variable env {
  default = {}
  type = map
}
variable es_configmap {
  type = string
}
variable es_service_account {
  type = string
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
variable termination_grace_period_seconds {
  default = 30
  type = number
}
variable pod_management_policy {
  default = "OrderedReady"
  type = string
}
variable publish_not_ready_addresses {
  default = false
  type = bool
}
variable pvc_access_modes {
  default = []
  type = list
}
variable pvc_storage_class_name {
  default = ""
  type = string
}
variable pvc_storage_size {
  default = "20Gi"
  type = string
}
variable service_name {
  type = string
}
variable service_name_headless {
  type = string
}
variable service_session_affinity {
  default = "None"
  type = string
}
variable transport_service_port {
  type = number
}
variable transport_service_target_port {
  type = number
}
variable service_type {
  default = "ClusterIP"
  type = string
}

/***
Define local variables.
***/
locals {
  pod_selector_label = "ps-${var.service_name}"
  svc_selector_label = "svc-${var.service_name_headless}"
  es_label = "es-cluster"
}

resource "kubernetes_stateful_set" "stateful_set" {
  metadata {
    name = var.service_name
    namespace = var.namespace
    # Labels attach to the StatefulSet.
    labels = {
      app = var.app_name
    }
  }
  #
  spec {
    replicas = var.replicas
    service_name = var.service_name_headless
    pod_management_policy = var.pod_management_policy
    revision_history_limit = var.revision_history_limit
    # Pod Selector - You must set the .spec.selector field of a StatefulSet to match the labels of
    # its .spec.template.metadata.labels. Failing to specify a matching Pod Selector will result in
    # a validation error during StatefulSet creation.
    selector {
      match_labels = {
        # It must match the labels in the Pod template (.spec.template.metadata.labels).
        pod_selector_lbl = local.pod_selector_label
      }
    }
    # The Pod template.
    template {
      metadata {
        # Labels attach to the Pod.
        labels = {
          app = var.app_name
          # It must match the label for the pod selector (.spec.selector.matchLabels).
          pod_selector_lbl = local.pod_selector_label
          # It must match the label selector of the Service.
          svc_selector_lbl = local.svc_selector_label
          es_lbl = local.es_label
          es_role_lbl = "es-data"
        }
      }
      #
      spec {
        service_account_name = var.es_service_account
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
        termination_grace_period_seconds = var.termination_grace_period_seconds
        init_container {
          name = "init-commands"
          image = "busybox:1.34.1"
          image_pull_policy = "IfNotPresent"
          command = [
            "/bin/sh",
            "-c",
            # Fix the permissions on the volume.
            # Increase the default vm.max_map_count to 262144.
            # Increase the max number of open file descriptors.
            "chown -R 1000:1000 /es-data; sysctl -w vm.max_map_count=262144; ulimit -n 65536"
          ]
          security_context {
            run_as_non_root = false
            run_as_user = 0
            run_as_group = 0
            read_only_root_filesystem = true
            privileged = true
          }
          volume_mount {
            name = "es-storage"
            mount_path = "/es-data"
          }
        }
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
            read_only_root_filesystem = false
            privileged = false
          }
          port {
            name = "transport"
            container_port = var.transport_service_target_port  # The port the app is listening.
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
          env_from {
            config_map_ref {
              # All key-value pairs of the ConfigMap are referenced.
              name = var.es_configmap
            }
          }
          dynamic "env" {
            for_each = var.env
            content {
              name = env.key
              value = env.value
            }
          }
          liveness_probe {
            tcp_socket {
              port = var.transport_service_target_port
            }
            initial_delay_seconds = 20
            period_seconds = 10
          }
          readiness_probe {
            http_get {
              path = "/_cluster/health"
              port = 9200
            }
            initial_delay_seconds = 20
            timeout_seconds = 5
          }
          volume_mount {
            name = "es-storage"
            mount_path = "/es-data"
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "es-storage"
        namespace = var.namespace
        labels = {
          app = var.app_name
        }
      }
      spec {
        access_modes = var.pvc_access_modes
        storage_class_name = var.pvc_storage_class_name
        resources {
          requests = {
            storage = var.pvc_storage_size
          }
        }
      }
    }
  }
}
