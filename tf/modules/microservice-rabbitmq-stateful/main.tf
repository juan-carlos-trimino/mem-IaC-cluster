/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.


The enabled_plugins file, which adds the rabbitmq_peer_discovery_k8s plugin and the standard management plugin, looks like this:

[rabbitmq_management,rabbitmq_peer_discovery_k8s].

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
variable "path_rabbitmq_files" {}
variable "rabbitmq_erlang_cookie" {}
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
# To relax the StatefulSet ordering guarantee while preserving its uniqueness and identity
# guarantee.
variable "pod_management_policy" {
  default = "OrderedReady"
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
variable "amqp_service_port" {
  type = number
}
variable "amqp_service_target_port" {
  type = number
}
variable "mgmt_service_port" {
  type = number
}
variable "mgmt_service_target_port" {
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

resource "kubernetes_secret" "rabbitmq_secret" {
  metadata {
    name = "${var.service_name}-secret"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  # Plain-text data.
  data = {
    rabbitmq_erlang_cookie = "${var.rabbitmq_erlang_cookie}"
  }
  type = "Opaque"
}

# A ServiceAccount is used by an application running inside a pod to authenticate itself with the
# API server. A default ServiceAccount is automatically created for each namespace; each pod is
# associated with exactly one ServiceAccount, but multiple pods can use the same ServiceAccount. A
# pod can only use a ServiceAccount from the same namespace.
#
# For cluster security, let’s constrain the cluster metadata this pod may read.
resource "kubernetes_service_account" "rabbitmq_service_account" {
  metadata {
    name = "${var.service_name}-service-account"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  secret {
    name = kubernetes_secret.rabbitmq_secret.metadata[0].name
  }
}

# Roles define WHAT can be done; role bindings define WHO can do it.
# The distinction between a Role/RoleBinding and a ClusterRole/ClusterRoleBinding is that the Role/
# RoleBinding is a namespaced resource; ClusterRole/ClusterRoleBinding is a cluster-level resource.
# A Role resource defines what actions can be taken on which resources; i.e., which types of HTTP
# requests can be performed on which RESTful resources.
resource "kubernetes_role" "rabbitmq_role" {
  metadata {
    name = "${var.service_name}-role"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  rule {
    # Endpoints are resources in the core apiGroup, which has no name - hence the "".
    api_groups = [""]
    verbs = ["get", "watch", "list"]
    # This rule pertains to endpoints; the plural form must be used when specifying resources.
    resources = ["endpoints"]
  }
}

resource "kubernetes_role_binding" "rabbitmq_role_binding" {
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
    name = kubernetes_role.rabbitmq_role.metadata[0].name
  }
  # ... and binds it to the specified ServiceAccount in the specified namespace.
  subject {
    # The default permissions for a ServiceAccount don't allow it to list or modify any resources.
    kind = "ServiceAccount"
    name = kubernetes_service_account.rabbitmq_service_account.metadata[0].name
    namespace = kubernetes_service_account.rabbitmq_service_account.metadata[0].namespace
  }
}

resource "kubernetes_config_map" "rabbitmq_config" {
  metadata {
    name = "${var.service_name}-config"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  data = {
    # The enabled_plugins file is usually located in the node data directory or under /etc,
    # together with configuration files. The file contains a list of plugin names ending with
    # a dot.
    "enabled_plugins" = "[rabbitmq_federation, rabbitmq_management, rabbitmq_peer_discovery_k8s]."
    "rabbitmq.conf" = "${file("${var.path_rabbitmq_files}/configmaps/rabbitmq.conf")}"
  }
}

/***
Declare a K8s stateful set to deploy a microservice; it instantiates the container for the
microservice into the K8s cluster.
$ kubectl get sts -n memories
***/
resource "kubernetes_stateful_set" "rabbitmq_stateful_set" {
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
    pod_management_policy = var.pod_management_policy
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
        service_account_name = kubernetes_service_account.rabbitmq_service_account.metadata[0].name
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
                    values = ["rs_rabbitmq"]
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
          # command = ["/usr/local/bin/docker-entrypoint.sh"]
          # Docker (CMD)
          # args = [
          #   "mongod",
          #   "--config", "${local.path_to_config}/mongod.conf",
          #   "--replSet", "rs0",
          #   "--bind_ip", "localhost,$(POD_NAME).${var.service_name}.${var.namespace}"
          # ]
          # Specifying ports in the pod definition is purely informational. Omitting them has no
          # effect on whether clients can connect to the pod through the port or not. If the
          # container is accepting connections through a port bound to the 0.0.0.0 address, other
          # pods can always connect to it, even if the port isn't listed in the pod spec
          # explicitly. Nonetheless, it is good practice to define the ports explicitly so that
          # everyone using the cluster can quickly see what ports each pod exposes.
          port {
            name = "amqp"
            container_port = var.amqp_service_target_port  # The port the app is listening.
            protocol = "TCP"
          }
          port {
            name = "mgmt"
            container_port = var.mgmt_service_target_port  # The port the app is listening.
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
            name = "RABBIT_POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          env {
            name = "RABBIT_POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }
          # When a node starts up, it checks whether it has been assigned a node name. If no value
          # was explicitly configured, the node resolves its hostname and prepends rabbit to it to
          # compute its node name.
          env {
            name = "RABBITMQ_NODENAME"
            value = "rabbit@$(RABBIT_POD_NAME).${var.service_name}.$(RABBIT_POD_NAMESPACE).svc.cluster.local"
          }
          env {
            name = "K8S_HOSTNAME_SUFFIX"
            value = ".${var.service_name}.$(RABBIT_POD_NAMESPACE).svc.cluster.local"
          }
          env {
            name = "RABBITMQ_ERLANG_COOKIE"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.rabbitmq_secret.metadata[0].name
                key = "rabbitmq_erlang_cookie"
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
          mmmmmmmmmmmmmmm
          volume_mount {
            name = "mongodb-storage"
            mount_path = "/data/db"
          }
          volume_mount {
            name = "configs"
            mount_path = "${local.path_to_config}"
            read_only = true
          }
          # volume_mount {
          #   name = "scripts"
          #   mount_path = "${local.path_to_scripts}"
          #   read_only = true
          # }
          volume_mount {
            name = "secrets"
            mount_path = "${local.path_to_secrets}"
            read_only = true
          }
        }
        volume {
          name = "configs"
          config_map {
            name = kubernetes_config_map.rabbitmq_config.metadata[0].name
            # Although ConfigMap should be used for non-sensitive configuration data, make the file
            # readable and writable only by the user and group that owns it.
            default_mode = "0440"  # Octal
            items {
              key = "mongod.conf"
              path = "mongod.conf"  #File name.
            }
          }
        }
        # volume {
        #   name = "scripts"
        #   config_map {
        #     name = kubernetes_config_map.scripts_files.metadata[0].name
        #     # Although ConfigMap should be used for non-sensitive configuration data, make the file
        #     # readable and writable only by the user and group that owns it.
        #     default_mode = "0440"  # Octal
        #     items {
        #       key = "entrypoint.sh"
        #       path = "entrypoint.sh"  #File name.
        #     }
        #     items {
        #       key = "start-replication.js"
        #       path = "start-replication.js"  #File name.
        #     }
        #   }
        # }
        volume {
          name = "secrets"
          secret {
            secret_name = kubernetes_secret.rabbitmq_secret.metadata[0].name
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
    # Since PersistentVolumes are cluster-level resources, they do not belong to any namespace, but
    # PersistentVolumeClaims can only be created in a specific namespace; they can only be used by
    # pods in the same namespace.
    volume_claim_template {
      metadata {
        name = "rabbitmq-storage"
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
$ kubectl run -it srvlookup --image=tutum/dnsutils --rm --restart=Never -- dig SRV mem-rabbitmq.memories.svc.cluster.local

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
      pod = kubernetes_stateful_set.rabbitmq_stateful_set.metadata[0].labels.pod
    }
    session_affinity = local.session_affinity
    port {
      name = "amqp"
      port = var.amqp_service_port  # Service port.
      target_port = var.amqp_service_target_port  # Pod port.
    }
    port {
      name = "mgmt"
      port = var.mgmt_service_port  # Service port.
      target_port = var.mgmt_service_target_port  # Pod port.
    }
    type = local.service_type
    cluster_ip = "None"  # Headless Service.
    publish_not_ready_addresses = var.publish_not_ready_addresses
  }
}
