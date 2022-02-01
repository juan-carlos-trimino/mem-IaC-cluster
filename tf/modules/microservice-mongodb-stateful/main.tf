/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "app_name" {}
variable "app_version" {}
variable "image_tag" {}
variable "mongodb_files" {}
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
variable "termination_grace_period_seconds" {
  default = 30
  type = number
}
# The primary use case for setting this field is to use a StatefulSet's Headless Service to
# propagate SRV records for its Pods without respect to their readiness for purpose of peer
# discovery.
variable "publish_not_ready_addresses" {
  default = "false"
  type = bool
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
  config_files = "/usr/mongodb/configs"
  script_files = "/docker-entrypoint-initdb.d"
}

# locals {
#   mongodb_secret = [{
#       env_name = "MONGO_INITDB_DATABASE"
#       data_name = "database"
#     },
#     {
#       env_name = "MONGO_INITDB_ROOT_USERNAME"
#       data_name = "root_username"
#     },
#     {
#       env_name = "MONGO_INITDB_ROOT_PASSWORD"
#       data_name = "root_password"
#     },
#     {
#       env_name = "MONGO_USERNAME"
#       data_name = "mongo_username"
#     },
#     {
#       env_name = "MONGO_PASSWORD"
#       data_name = "mongo_password"
#     }]
# }

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
    root_username = "${var.mongodb_root_username}"
    root_password = "${var.mongodb_root_password}"
    mongodb_username = "${var.mongodb_username}"
    mongodb_password = "${var.mongodb_password}"
    # users_list = "${var.mongodb_database}:${var.mongodb_root_username},readWrite:${var.mongodb_root_password}"
  }
  type = "Opaque"
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

resource "kubernetes_config_map" "conf_files" {
  metadata {
    name = "${var.service_name}-conf-files"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  data = {
    "mongod.conf" = "${file("${var.mongodb_files}/configmaps/mongod.conf")}"
  }
}

resource "kubernetes_config_map" "script_files" {
  metadata {
    name = "${var.service_name}-script-files"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  data = {
    "entrypoint.sh" = "${file("${var.mongodb_files}/scripts/entrypoint.sh")}"
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
    "ensure-users.js" = "${file("${var.mongodb_files}/scripts/ensure-users.js")}"
  }
}

/***
Declare a K8s stateful set to deploy a microservice; it instantiates the container for the
microservice into the K8s cluster.
$ kubectl get sts -n memories
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
        # init_container {
        #   name = "tbd"
        #   image = "busybox:1.35"
        #   image_pull_policy = "IfNotPresent"
        #   # command = ["/bin/sh"]
        #   # args = ["-c", "chgrp -R 0 /var/log/mongodb && chmod -R g=u /var/log/mongodb"]
        #   # command = ["/bin/chgrp -R 0 /var/log/mongodb && /bin/chmod -R g=u /var/log/mongodb"]
        #   command = ["sh", "-c", "echo abc"]
        #   # volume_mount {
        #   #   name = "var-dir"
        #   #   mount_path = "/var/log/mongodb"
        #   #   # sub_path   = ""
        #   # }
        # }
        affinity {
          # The pod anti-affinity rule says that the pod prefers to not schedule onto a node if
          # that node is already running a pod with label having key 'replicaset' and value
          # 'running_one'.
          pod_anti_affinity {
            # Defines a preferred rule.
            preferred_during_scheduling_ignored_during_execution {
              # Specifies a weight for a preferred rule. The node with the highest weight is
              # preferred.
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    # Description of the pod label that determines when the anti-affinity rule
                    # applies. Specifies a key and value for the label.
                    key = "replicaset"
                    # The operator represents the relationship between the label on the existing
                    # pod and the set of values in the matchExpression parameters in the
                    # specification for the new pod. Can be In, NotIn, Exists, or DoesNotExist.
                    operator = "In"
                    values = ["running_one"]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }
        # jct
        # automount_service_account_token = false
        termination_grace_period_seconds = var.termination_grace_period_seconds
        # The security settings that is specified for a Pod apply to all Containers in the Pod.
        # security_context {
        #   # run_as_user = 1010
        #   # run_as_group = 1001
        #   fs_group = 0
        # }
        container {
          name = var.service_name
          image = var.image_tag
          # security_context {
          #   run_as_non_root = true
          #   # run_as_user = 1001
          # }
          # image_pull_policy = "IfNotPresent"
          # Docker (ENTRYPOINT)
          command = [ "${local.script_files}/entrypoint.sh" ]
          # Docker (CMD)
          args = ["--config", "${local.config_files}/mongod.conf"]
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
          # Using the Pod field as a value for the environment variable.
          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          env {
            name = "MONGO_INITDB_ROOT_USERNAME_FILE"
            value = "/usr/mongodb/secrets/MONGODB_ROOT_USERNAME"
          }
          env {
            name = "MONGO_INITDB_ROOT_PASSWORD_FILE"
            value = "/usr/mongodb/secrets/MONGODB_ROOT_PASSWORD"
          }
          env {
            name = "MONGODB_INITIAL_PRIMARY_HOST"
            value = "$(POD_NAME).${var.service_name}.${var.namespace}.svc.cluster.local"
          }
          env {
            name = "MONGODB_ADVERTISED_HOSTNAME"
            value = "$(MONGODB_INITIAL_PRIMARY_HOST)"
          }
          env {
            name = "MONGODB_PORT_NUMBER"
            value = "${var.service_target_port}"
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

          # volume_mount {
          #   name = "var-dir"
          #   mount_path = "/var/log/mongodb"
          #   # sub_path   = ""
          # }

          volume_mount {
            name = "mongodb-storage"
            mount_path = "/data/db"
          }
          # Mounting an individual ConfigMap entry as a file without hiding other files in the
          # directory.
          volume_mount {
            name = "configs"
            mount_path = "${local.config_files}/mongod.conf"
            sub_path = "mongod.conf"
            read_only = true
          }
          volume_mount {
            name = "scripts"
            mount_path = "${local.script_files}/entrypoint.sh"
            sub_path = "entrypoint.sh"
            read_only = true
          }
          volume_mount {
            name = "secrets"
            mount_path = "/usr/mongodb/secrets"
            read_only = true
          }
        }

        # volume {
        #   name = "var-dir"
        #   empty_dir {}
        # }


        volume {
          name = "configs"
          config_map {
            name = kubernetes_config_map.conf_files.metadata[0].name
            # Although ConfigMap should be used for non-sensitive configuration data, make the file
            # readable and writable only by the user and group that owns it.
            default_mode = "0440"  # Octal
          }
        }
        volume {
          name = "scripts"
          config_map {
            name = kubernetes_config_map.script_files.metadata[0].name
            # Although ConfigMap should be used for non-sensitive configuration data, make the file
            # readable and writable only by the user and group that owns it.
            default_mode = "0440"  # Octal
          }
        }
        volume {
          name = "secrets"
          secret {
            secret_name = kubernetes_secret.mongodb_secret.metadata[0].name
            default_mode = "0440"  # Octal
            items {
              key = "root_username"
              path = "MONGODB_ROOT_USERNAME"
            }
            items {
              key = "root_password"
              path = "MONGODB_ROOT_PASSWORD"
            }
            items {
              key = "mongodb_username"
              path = "MONGODB_USERNAME"
            }
            items {
              key = "mongodb_password"
              path = "MONGODB_PASSWORD"
            }
            # items {
            #   key = "users_list"
            #   path = "MONGODB_USERS_LIST"
            # }
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
    publish_not_ready_addresses = var.publish_not_ready_addresses
  }
}
