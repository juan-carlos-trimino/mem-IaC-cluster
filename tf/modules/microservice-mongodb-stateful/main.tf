/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "app_name" {}
variable "app_version" {}
variable "image_tag" {}
variable "config_file_path" {}
variable "mongodb_database" {}
variable "mongodb_root_username" {}
variable "mongodb_root_password" {}
variable "mongodb_username" {}
variable "mongodb_password" {}
variable "namespace" {
  default = "default"
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
variable "pvc_name" {
  default = ""
}
variable "pvc_access_modes" {
  default = []
  type = list
}
variable "pvc_storage_class_name" {
  default = ""
}
variable "pvc_storage_size" {
  default = "20Gi"
}
variable "service_name" {
  default = ""
}
variable "service_port" {
  type = number
}
variable "service_target_port" {
  type = number
}
#
locals {
  # service_name = "service-mongodb"
  # The service normally forwards each connection to a randomly selected backing pod. To
  # ensure that connections from a particular client are passed to the same Pod each time,
  # set the service's sessionAffinity property to ClientIP instead of None (default).
  # Session affinity and Web Browsers (for LoadBalancer Services)
  # Since the service is now exposed externally, accessing it with a web browser will hit
  # the same pod every time. If the sessionAffinity is set to None, then why? The browser
  # is using keep-alive connections and sends all its requests through a single connection.
  # Services work at the connection level, and when a connection to a service is initially
  # open, a random pod is selected and then all network packets belonging to that connection
  # are sent to that single pod. Even with the sessionAffinity set to None, the same pod will
  # always get hit (until the connection is closed).
  session_affinity = "None"
  service_type = "ClusterIP"
  config_file = "/usr/mongodb/config/mongod.conf"
}

/***
Because PersistentVolumeClaim (PVC) can only be created in a specific namespace, they can only be
used by pods in the same namespace.
***/
# resource "kubernetes_persistent_volume_claim" "mongodb_claim" {
#   metadata {
#     name = var.pvc_name
#     namespace = var.namespace
#     labels = {
#       app = var.app_name
#     }
#   }
#   spec {
#     # Empty string must be explicitly set otherwise default StorageClass will be set.
#     # -------------------------------------------------------------------------------
#     # StorageClass enables dynamic provisioning of PersistentVolumes (PV).
#     # (1) When creating a claim, the PV is created by the provisioner referenced in the
#     #     StorageClass resource; the provisioner is used even if an existing manually
#     #     provisioned PV matches the PVC.
#     # (2) The default storage class is used to dynamically provision a PV if the PVC does not
#     #     explicitly state which storage class name to use.
#     # (3) To bind the PVC to a pre-provisioned PV instead of dynamically provisioning a new one,
#     #     specify an empty string as the storage class name; effectively disable dynamic
#     #     provisioning.
#     storage_class_name = var.pvc_storage_class_name
#     access_modes = var.pvc_access_modes
#     resources {
#       requests = {
#         storage = var.pvc_storage_size
#       }
#     }
#   }
# }

locals {
  mongodb_secret = [{
      env_name = "MONGO_INITDB_DATABASE"
      data_name = "database"
    },
    {
      env_name = "MONGO_INITDB_ROOT_USERNAME"
      data_name = "root_username"
    },
    {
      env_name = "MONGO_INITDB_ROOT_PASSWORD"
      data_name = "root_password"
    },
    {
      env_name = "MONGO_USERNAME"
      data_name = "username"
    },
    {
      env_name = "MONGO_PASSWORD"
      data_name = "password"
    }]
}

resource "kubernetes_secret" "mongodb_secret" {
  metadata {
    name = "${var.service_name}-secret"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  # Plain-text data.
  data = {
    #database = "${var.mongodb_database}"
    root_username = "${var.mongodb_root_username}"
    root_password = "${var.mongodb_root_password}"
    username = "${var.mongodb_username}"
    password = "${var.mongodb_password}"
    users_list = "${var.mongodb_database}:${var.mongodb_root_username},readWrite:${var.mongodb_root_password}"
  }
  type = "kubernetes.io/basic-auth"
}

# A ServiceAccount is used by an application running inside a pod to authenticate itself with the
# API server. A default ServiceAccount is automatically created for each namespace; each pod is
# associated with exactly one ServiceAccount, but multiple pods can use the same ServiceAccount. A
# pod can only use a ServiceAccount from the same namespace.
resource "kubernetes_service_account" "mongodb_service_account" {
  metadata {
    name = "${var.service_name}-service-account"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  secret {
    name = "${kubernetes_secret.mongodb_secret.metadata[0].name}"
  }
}

resource "kubernetes_config_map" "mongod_conf" {
  metadata {
    name = "${var.service_name}-mongodb-conf"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  data = {
    "mongod.conf" = "${file("${var.config_file_path}/configmaps/mongod.conf")}"
  }
}

resource "kubernetes_config_map" "ensure_users" {
  metadata {
    name = "${var.service_name}-ensure-users"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  data = {
    "ensure-users.js" = "${file("${var.config_file_path}/scripts/ensure-users.js")}"
  }
}

/***
Declare a K8s stateful set to deploy a microservice; it instantiates the container for the
microservice into the K8s cluster.
***/
resource "kubernetes_stateful_set" "mongodb_stateful_set" {
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
    service_name = var.service_name
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
        affinity {
          # https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/
          # https://docs.openshift.com/container-platform/3.11/admin_guide/scheduling/pod_affinity.html
          # The pod anti-affinity rule says that the pod prefers to not schedule onto a node if
          # that node is already running a pod with label having key 'security' and value 'S2'.
          pod_anti_affinity {
            # Defines a preferred rule.
            preferred_during_scheduling_ignored_during_execution {
              # Specifies a weight for a preferred rule. The node with the highest weight is preferred.
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    # Description of the pod label that determines when the anti-affinity rule applies. Specify a key and value for the label.
                    key = "security"
                    # The operator represents the relationship between the label on the existing pod and the set of values in the matchExpression parameters in the specification for the new pod. Can be In, NotIn, Exists, or DoesNotExist.
                    operator = "In"
                    values = ["S2"]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }
        # jct
        # automount_service_account_token = false
        # termination_grace_period_seconds = 10
        container {
          image = var.image_tag
          args = ["--config", "${local.config_file}"]
          name = var.service_name
          # Specifying ports in the pod definition is purely informational. Omitting them has no
          # effect on whether clients can connect to the pod through the port or not. If the
          # container is accepting connections through a port bound to the 0.0.0.0 address, other
          # pods can always connect to it, even if the port isn't listed in the pod spec
          # explicitly. Nonetheless, it is good practice to define the ports explicitly so that
          # everyone using the cluster can quickly see what ports each pod exposes.
          port {
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
          env {
            name = "MONGO_INITDB_ROOT_USERNAME_FILE"
            value = "/usr/mongodb/secrets/MONGO_ROOT_USERNAME"
          }
          env {
            name = "MONGO_INITDB_ROOT_PASSWORD_FILE"
            value = "/usr/mongodb/secrets/MONGO_ROOT_PASSWORD"
          }
          # dynamic "env" {
          #   for_each = local.mongodb_secret
          #   content {
          #     name = env.value.env_name
          #     value_from {
          #       secret_key_ref {
          #         name = kubernetes_secret.mongodb_secret.metadata[0].name
          #         key = env.value.data_name
          #       }
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
          volume_mount {
            name = "mongodb-storage"
            mount_path = "/usr/mongodb/data/db"  #"$(DATA_FILE_PATH)"   "/aaa/data/db"     #"$(mongodb.conf.storage.dbPath)"    
          }
          # Mounting an individual ConfigMap entry as a file without hiding other files in the
          # directory.
          volume_mount {
            name = "config"
            mount_path = local.config_file
            sub_path = "mongod.conf"
            read_only = true
          }
          # volume_mount {
          #   name = "scripts"
          #   mount_path = "/usr/mongodb/docker-entrypoint-initdb.d"
          #   sub_path = "ensure-users.js"
          #   read_only = true
          # }
          volume_mount {
            name = "secrets"
            mount_path = "/usr/mongodb/secrets"
            read_only = true
          }
        }
        #
        # volume {
        #   name = "mongodb-storage"
        #   persistent_volume_claim {
        #     claim_name = kubernetes_persistent_volume_claim.mongodb_claim.metadata[0].name
        #   }
        # }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.mongod_conf.metadata[0].name
            # Although ConfigMap should be used for non-sensitive configuration data, make the file
            # readable and writable only by the user and group that owns it.
            default_mode = "0660"  # Octal
          }
        }
        # volume {
        #   name = "scrips"
        #   config_map {
        #     name = kubernetes_config_map.ensure_users.metadata[0].name
        #     # Although ConfigMap should be used for non-sensitive configuration data, make the file
        #     # readable and writable only by the user and group that owns it.
        #     default_mode = "0660"  # Octal
        #   }
        # }
        volume {
          name = "secrets"
          secret {
            secret_name = kubernetes_secret.mongodb_secret.metadata[0].name
            default_mode = "0440"  # Octal
            items {
              key = "root_username"
              path = "MONGO_ROOT_USERNAME"
            }
            items {
              key = "root_password"
              path = "MONGO_ROOT_PASSWORD"
            }
            items {
              key = "users_list"
              path = "MONGO_USERS_LIST"
            }
          }
        }
      }
    }
    # This template will be used to create a PersistentVolumeClaim for each pod.
    volume_claim_template {
      metadata {
        name = "mongodb-storage"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        # storage_class_name = "standard"
        resources {
          requests = {
            storage = var.pvc_storage_size
          }
        }
      }
    }
  }
}

/***
A StatefulSet requires a corresponding governing headless Service that's used to provide the actual
network identity to each pod. Through this Service, each pod gets its own DNS entry thereby
allowing its peers in the cluster to address the pod by its hostname. For example, if the governing
Service belongs to the default namespace and is called service1, and the pod name is pod-0, the pod
can be reached by its fully qualified domain name of pod-0.service1.default.svc.cluster.local.

To list the SRV records for the stateful pods, perform a DNS lookup from inside a pod running in
the cluster:
$ kubectl run -it srvlookup --image=tutum/dnsutils --rm --restart=Never -- dig SRV mem-mongodb.memories.svc.cluster.local

where 'dig SRV <service-name>.<namespace>.svc.cluster.local'
***/
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
      pod = kubernetes_stateful_set.mongodb_stateful_set.metadata[0].labels.pod
    }
    session_affinity = local.session_affinity
    port {
      port = var.service_port  # Service port.
      target_port = var.service_target_port  # Pod port.
    }
    type = local.service_type
    cluster_ip = "None"  # Headless Service.
    # The primary use case for setting this field is to use a StatefulSet's Headless Service to
    # propagate SRV records for its Pods without respect to their readiness for purpose of peer
    # discovery.
    publish_not_ready_addresses = true
  }
}
