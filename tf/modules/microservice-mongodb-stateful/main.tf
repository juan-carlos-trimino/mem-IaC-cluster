/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "app_name" {}
variable "app_version" {}
variable "image_tag" {
  default = ""
}
variable "dir_name" {}
variable "cr_login_server" {}
variable "cr_username" {}
variable "cr_password" {}
variable "path_mongodb_files" {}
variable "mongodb_database" {}
variable "mongo_initdb_root_username" {}
variable "mongo_initdb_root_password" {}
variable "mongodb_username" {}
variable "mongodb_password" {}
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
  session_affinity = "None"
  service_type = "ClusterIP"
  path_to_secrets = "/mongodb/secrets"
  path_to_config = "/mongodb/configs"
  path_to_scripts = "/docker-entrypoint-initdb.d"
}

/***
Define local variables.
***/
locals {
  image_tag = (
                var.image_tag == "" ?
                "${var.cr_login_server}/${var.cr_username}/${var.service_name}:${var.app_version}" :
                var.image_tag
              )
}

/***
Build the Docker image.
Use null_resource to create Terraform resources that do not have any particular resourse type.
Use local-exec to invoke commands on the local workstation.
Use timestamp to force the Docker image to build.
***/
resource "null_resource" "docker_build" {
  triggers = {
    always_run = timestamp()
  }
  #
  provisioner "local-exec" {
    command = "docker build -t ${local.image_tag} --file ${var.dir_name}/Dockerfile-prod ${var.dir_name}"
  }
}

/***
Login to the Container Registry.
***/
resource "null_resource" "docker_login" {
  depends_on = [
    null_resource.docker_build
  ]
  triggers = {
    always_run = timestamp()
  }
  #
  provisioner "local-exec" {
    command = "docker login ${var.cr_login_server} -u ${var.cr_username} -p ${var.cr_password}"
  }
}

/***
Push the image to the Container Registry.
***/
resource "null_resource" "docker_push" {
  depends_on = [
    null_resource.docker_login
  ]
  triggers = {
    always_run = timestamp()
  }
  #
  provisioner "local-exec" {
    command = "docker push ${local.image_tag}"
  }
}

resource "kubernetes_secret" "registry_credentials" {
  metadata {
    name = "${var.service_name}-registry-credentials"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "${var.cr_login_server}" = {
          auth = base64encode("${var.cr_username}:${var.cr_password}")
        }
      }
    })
  }
  type = "kubernetes.io/dockerconfigjson"
}

resource "kubernetes_secret" "mongodb_secret" {
  metadata {
    name = "${var.service_name}-secrets"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  # Plain-text data.
  data = {
    mongo_initdb_root_username = "${var.mongo_initdb_root_username}"
    mongo_initdb_root_password = "${var.mongo_initdb_root_password}"
    mongo_replicaset_key = "${file("${var.path_mongodb_files}/certs/mongo-replicaset.key")}"
  }
  type = "Opaque"
}

# A ServiceAccount is used by an application running inside a pod to authenticate itself with the
# API server. A default ServiceAccount is automatically created for each namespace; each pod is
# associated with exactly one ServiceAccount, but multiple pods can use the same ServiceAccount. A
# pod can only use a ServiceAccount from the same namespace.
#
# For cluster security, let’s constrain the cluster metadata this pod may read.
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
    "mongod.conf" = "${file("${var.path_mongodb_files}/configmaps/mongod.conf")}"
  }
}

resource "kubernetes_config_map" "scripts_files" {
  metadata {
    name = "${var.service_name}-script-files"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  data = {
    "entrypoint.sh" = "${file("${var.path_mongodb_files}/scripts/entrypoint.sh")}"
    "start-replication.js" = "${file("${var.path_mongodb_files}/scripts/start-replication.js")}"
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
        service_account_name = kubernetes_service_account.mongodb_service_account.metadata[0].name
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
                # By default, the label selector only matches pods in the same namespace as the pod
                # that is being scheduled. To select pods from other namespaces, add the
                # appropriate namespace(s) in the namespaces field.
                namespaces = ["${var.namespace}"]
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }
        termination_grace_period_seconds = var.termination_grace_period_seconds
        # The security settings that is specified for a Pod apply to all Containers in the Pod.
        # security_context {
        #   # run_as_user = 1010
        #   # run_as_group = 1010
        #   fs_group = 0
        # }
        image_pull_secrets {
          name = kubernetes_secret.registry_credentials.metadata[0].name
        }
        container {
          name = var.service_name
          image = local.image_tag
          image_pull_policy = var.imagePullPolicy
          # security_context {
          #   run_as_non_root = true
          #   # run_as_user = 1001
          # }
          # Docker (ENTRYPOINT)
          command = ["/usr/local/bin/docker-entrypoint.sh"]
          # Docker (CMD)
          args = [
            "mongod",
            "--config", "${local.path_to_config}/mongod.conf",
            "--replSet", "rs0",
            "--bind_ip", "localhost,$(POD_NAME).${var.service_name}.${var.namespace}"
          ]
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
            name = "MONGODB_INITIAL_PRIMARY_HOST"
            value = "$(POD_NAME).${var.service_name}.${var.namespace}.svc.cluster.local"
          }
          # env {
          #   name = "MONGO_INITDB_ROOT_USERNAME_FILE"
          #   value = "${local.path_to_secrets}/mongo-initdb-root-username"
          # }
          # env {
          #   name = "MONGO_INITDB_ROOT_PASSWORD_FILE"
          #   value = "${local.path_to_secrets}/mongo-initdb-root-password"
          # }
          env {
            name = "MONGODB_ADVERTISED_HOSTNAME"
            value = "$(MONGODB_INITIAL_PRIMARY_HOST)"
          }
          env {
            name = "MONGODB_PORT_NUMBER"
            value = "${var.service_target_port}"
          }
          dynamic "env" {
            for_each = var.env
            content {
              name = env.key
              value = env.value
            }
          }
          volume_mount {
            name = "mongodb-storage"
            mount_path = "/data/db"
          }
          volume_mount {
            name = "configs"
            mount_path = "${local.path_to_config}"
            read_only = true
          }
          volume_mount {
            name = "scripts"
            mount_path = "${local.path_to_scripts}"
            read_only = true
          }
          volume_mount {
            name = "secrets"
            mount_path = "${local.path_to_secrets}"
            read_only = true
          }
        }
        volume {
          name = "configs"
          config_map {
            name = kubernetes_config_map.conf_files.metadata[0].name
            # Although ConfigMap should be used for non-sensitive configuration data, make the file
            # readable and writable only by the user and group that owns it.
            default_mode = "0440"  # Octal
            items {
              key = "mongod.conf"
              path = "mongod.conf"  #File name.
            }
          }
        }
        volume {
          name = "scripts"
          config_map {
            name = kubernetes_config_map.scripts_files.metadata[0].name
            # Although ConfigMap should be used for non-sensitive configuration data, make the file
            # readable and writable only by the user and group that owns it.
            default_mode = "0440"  # Octal
            items {
              key = "entrypoint.sh"
              path = "entrypoint.sh"  #File name.
            }
            items {
              key = "start-replication.js"
              path = "start-replication.js"  #File name.
            }
          }
        }
        volume {
          name = "secrets"
          secret {
            secret_name = kubernetes_secret.mongodb_secret.metadata[0].name
            # default_mode = "0600"  # Octal
            default_mode = "0440"  # Octal
            items {
              key = "mongo_initdb_root_username"
              path = "mongo-initdb-root-username"  #File name.
            }
            items {
              key = "mongo_initdb_root_password"
              path = "mongo-initdb-root-password"
            }
            items {
              key = "mongo_replicaset_key"
              path = "mongo-replicaset.key"
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
