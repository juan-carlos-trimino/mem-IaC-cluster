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
variable pod_management_policy {
  default = "OrderedReady"
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
}
variable pvc_storage_size {
  default = "20Gi"
}
variable service_name {
  default = ""
}
variable service_name_headless {
  default = ""
}
variable service_session_affinity {
  default = "None"
}
variable transport_service_port {
  type = number
}
variable transport_service_target_port {
  type = number
}
variable service_type {
  default = "ClusterIP"
}

/***
Define local variables.
***/
locals {
  pod_selector_label = "ps-${var.service_name}"
  svc_label = "svc-${var.service_name_headless}"
  es_label = "es-cluster"
}

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
    resources = ["endpoints", "services", "namespaces"]
  }
  rule {
    api_groups = ["security.openshift.io"]
    verbs = ["use"]
    resources = ["securitycontextconstraints"]
    resource_names = ["mem-elasticsearch-scc"]
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
    # The name of the service that governs this StatefulSet.
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
          # It must match the label for the pod selector (.spec.selector.matchLabels).
          pod_selector_lbl = local.pod_selector_label
          # It must match the label selector of the Service.
          svc_lbl = local.svc_label
          es_lbl = local.es_label
          es_role_lbl = "es-data"
        }
      }
      #
      spec {
        service_account_name = kubernetes_service_account.service_account.metadata[0].name
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
        # Fix the permissions on the volume.
        init_container {
          name = "fix-permissions"
          image = "busybox:1.34.1"
          image_pull_policy = "IfNotPresent"
          command = ["/bin/sh", "-c", "chown -R 1000:1000 /es-data"]
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
        # Increase the default vm.max_map_count to 262144
        init_container {
          name = "init-sysctl"
          image = "busybox:1.34.1"
          image_pull_policy = "IfNotPresent"
          command = ["sysctl", "-w", "vm.max_map_count=262144"]
          security_context {
            run_as_non_root = false
            run_as_user = 0
            run_as_group = 0
            read_only_root_filesystem = true
            privileged = true
          }
        }
        # Increase the max number of open file descriptors.
        init_container {
          name = "increase-fd"
          image = "busybox:1.34.1"
          image_pull_policy = "IfNotPresent"
          command = ["/bin/sh", "-c", "ulimit -n 65536"]
          security_context {
            run_as_non_root = false
            run_as_user = 0
            run_as_group = 0
            read_only_root_filesystem = true
            privileged = true
          }
        }
        container {
          name = var.service_name
          image = var.image_tag
          image_pull_policy = var.imagePullPolicy
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
          dynamic "env" {
            for_each = var.env
            content {
              name = env.key
              value = env.value
            }
          }
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
          # volume_mount {
          #   name = "elasticsearch-storage"
          #   mount_path = "/usr/share/elasticsearch/data"
          # }
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
