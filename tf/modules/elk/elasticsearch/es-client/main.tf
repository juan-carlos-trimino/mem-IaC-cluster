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
variable es_username {
  type = string
  sensitive = true
}
variable es_password {
  type = string
  sensitive = true
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
  rs_label = "rs-${var.service_name}"
  svc_label = "svc-${var.service_name}"
  es_label = "es-cluster"
}

resource "kubernetes_secret" "secret" {
  metadata {
    name = "${var.service_name}-secret"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  # Plain-text data.
  data = {
    es_username = var.es_username
    es_password = var.es_password
  }
  type = "Opaque"
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
          # command = [
          #   "/bin/sh",
          #   "-c",
          #   # "./bin/elasticsearch-certutil ca; ./bin/elasticsearch cert --ca es-ca.p12; cp es-ca.p12 /es-data/certs/es-ca.p12"
          #   "./bin/elasticsearch-certutil --silent cert --ca --out /es-data/certs/es-ca.p12 --ca-pass \"\""
          # ]
          port {
            name = "http"
            container_port = var.http_service_target_port  # The port the app is listening.
            protocol = "TCP"
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
    port {
      name = "transport"
      port = var.transport_service_port  # Service port.
      target_port = var.transport_service_target_port  # Pod port.
      protocol = "TCP"
    }
    type = var.service_type
  }
}
