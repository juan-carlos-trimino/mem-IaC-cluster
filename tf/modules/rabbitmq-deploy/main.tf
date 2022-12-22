/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "app_name" {}
variable "app_version" {}
# variable "image_tag" {
#   default = ""
# }
variable "image_tag" {}
variable "path_rabbitmq_files" {}
variable "rabbitmq_erlang_cookie" {}
variable "rabbitmq_default_pass" {}
variable "rabbitmq_default_user" {}
variable "namespace" {
  default = "default"
}
# variable "dir_name" {}
# variable "cr_login_server" {}
# variable "cr_username" {}
# variable "cr_password" {}
variable "dns_name" {
  default = ""
}
variable "readiness_probe" {
  default = []
  type = list(object({
    http_get = list(object({
      # Host name to connect to, defaults to the pod IP.
      #host = string
      # Path to access on the HTTP server. Defaults to /.
      path = string
      # Name or number of the port to access on the container. Number must be in the range 1 to
      # 65535.
      port = number
      # Scheme to use for connecting to the host (HTTP or HTTPS). Defaults to HTTP.
      scheme = string
    }))
    # Number of seconds after the container has started before liveness or readiness probes are
    # initiated. Defaults to 0 seconds. Minimum value is 0.
    initial_delay_seconds = number
    # How often (in seconds) to perform the probe. Default to 10 seconds. Minimum value is 1.
    period_seconds = number
    # Number of seconds after which the probe times out. Defaults to 1 second. Minimum value is 1.
    timeout_seconds = number
    # When a probe fails, Kubernetes will try failureThreshold times before giving up. Giving up in
    # case of liveness probe means restarting the container. In case of readiness probe the Pod
    # will be marked Unready. Defaults to 3. Minimum value is 1.
    failure_threshold = number
    # Minimum consecutive successes for the probe to be considered successful after having failed.
    # Defaults to 1. Must be 1 for liveness and startup Probes. Minimum value is 1.
    success_threshold = number
  }))
}
# Be aware that the default imagePullPolicy depends on the image tag. If a container refers to the
# latest tag (either explicitly or by not specifying the tag at all), imagePullPolicy defaults to
# Always, but if the container refers to any other tag, the policy defaults to IfNotPresent.
#
# When using a tag other that latest, the imagePullPolicy property must be set if changes are made
# to an image without changing the tag. Better yet, always push changes to an image under a new
# tag.
variable image_pull_policy {
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
variable "service_name" {
  default = ""
}
# The ServiceType allows to specify what kind of Service to use: ClusterIP (default),
# NodePort, LoadBalancer, and ExternalName.
variable "service_type" {
  default = "ClusterIP"
}
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
variable "service_session_affinity" {
  default = "None"
}
# variable "service_port" {
#   type = number
#   default = 80
# }
# variable "service_target_port" {
#   type = number
#   default = 8080
# }
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

/***
Define local variables.
***/
# locals {
#   image_tag = (
#                 var.image_tag == "" ?
#                 "${var.cr_login_server}/${var.cr_username}/${var.service_name}:${var.app_version}" :
#                 var.image_tag
#               )
# }




resource "null_resource" "scc-rabbitmq" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "oc apply -f ./utility-files/rabbitmq/mem-rabbitmq-scc.yaml"
  }
  #
  provisioner "local-exec" {
    when = destroy
    command = "oc delete scc mem-rabbitmq-scc"
  }
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
    #   "kubernetes.io/enforce-mountable-secrets" = true
    # }
  }
  # secret {
  #   name = kubernetes_secret.secret.metadata[0].name
  # }
}

# Roles define WHAT can be done; role bindings define WHO can do it.
# The distinction between a Role/RoleBinding and a ClusterRole/ClusterRoleBinding is that the Role/
# RoleBinding is a namespaced resource; ClusterRole/ClusterRoleBinding is a cluster-level resource.
# A Role resource defines what actions can be taken on which resources; i.e., which types of HTTP
# requests can be performed on which RESTful resources.
#
# RabbitMQ's Kubernetes peer discovery plugin relies on the Kubernetes API as a data source. On
# first boot, every node will try to discover their peers using the Kubernetes API and attempt to
# join them. Nodes that finish booting emit a Kubernetes event to make it easier to discover such
# events in cluster activity (event) logs.
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
    # This rule pertains to endpoints; the plural form must be used when specifying resources.
    # The peer discovery plugin requires that the pod it runs in has rights to query the K8s API
    # endpoints resource (https://github.com/rabbitmq/rabbitmq-peer-discovery-k8s).
    resources = ["endpoints"]
  }
  rule {
    api_groups = [""]
    verbs = ["create"]
    resources = ["events"]
  }
  rule {
    api_groups = ["security.openshift.io"]
    verbs = ["use"]
    resources = ["securitycontextconstraints"]
    resource_names = ["mem-mongodb-scc"]
  }
}

# Bind the role to the service account.
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



/***
Build the Docker image.
Use null_resource to create Terraform resources that do not have any particular resourse type.
Use local-exec to invoke commands on the local workstation.
Use timestamp to force the Docker image to build.
***/
# resource "null_resource" "docker_build" {
#   triggers = {
#     always_run = timestamp()
#   }
#   #
#   provisioner "local-exec" {
#     command = "docker build -t ${local.image_tag} --file ${var.dir_name}/Dockerfile-prod ${var.dir_name}"
#   }
# }

/***
Login to the Container Registry.
***/
# resource "null_resource" "docker_login" {
#   depends_on = [
#     null_resource.docker_build
#   ]
#   triggers = {
#     always_run = timestamp()
#   }
#   #
#   # provisioner "local-exec" {
#   #   command = "echo ${var.cr_password} >> pw.txt"
#   # }
#   provisioner "local-exec" {
#     # command = "docker login ${var.cr_login_server} -T -u ${var.cr_username} --password-stdin"
#     command = "docker login ${var.cr_login_server} -u ${var.cr_username} -p ${var.cr_password}"
#   }
# }

/***
Push the image to the Container Registry.
***/
# resource "null_resource" "docker_push" {
#   depends_on = [
#     null_resource.docker_login
#   ]
#   triggers = {
#     always_run = timestamp()
#   }
#   #
#   provisioner "local-exec" {
#     command = "docker push ${local.image_tag}"
#   }
# }

# resource "kubernetes_secret" "registry_credentials" {
#   metadata {
#     name = "${var.service_name}-registry-credentials"
#     namespace = var.namespace
#     labels = {
#       app = var.app_name
#     }
#   }
#   data = {
#     ".dockerconfigjson" = jsonencode({
#       auths = {
#         "${var.cr_login_server}" = {
#           auth = base64encode("${var.cr_username}:${var.cr_password}")
#         }
#       }
#     })
#   }
#   type = "kubernetes.io/dockerconfigjson"
# }

resource "kubernetes_secret" "secret" {
  metadata {
    name = "${var.service_name}-secret"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  # Plain-text data.
  # RabbitMQ nodes and the CLI tools use a cookie to determine whether they are allowed to
  # communicate with each other. For two nodes to be able to communicate, they must have the same
  # shared secret called the Erlang cookie.
  data = {
    cookie = "${var.rabbitmq_erlang_cookie}"
    pass = "${var.rabbitmq_default_pass}"
    user = "${var.rabbitmq_default_user}"
  }
  type = "Opaque"
}

# The ConfigMap passes to the rabbitmq daemon a bootstrap configuration which mainly defines peer
# discovery and connectivity settings.
resource "kubernetes_config_map" "config" {
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
    "enabled_plugins" = "[rabbitmq_management, rabbitmq_peer_discovery_k8s]."
    # "rabbitmq.conf" = "${file("${var.path_rabbitmq_files}/configmaps-deployment/rabbitmq.conf")}"
    "rabbitmq.conf" = "${file("${var.path_rabbitmq_files}/rabbitmq.conf")}"
  }
}

/***
Declare a K8s deployment to deploy a microservice; it instantiates the container for the
microservice into the K8s cluster.
***/
resource "kubernetes_deployment" "deployment" {
  # depends_on = [
  #   null_resource.docker_push
  # ]
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
        # image_pull_secrets {
        #   name = kubernetes_secret.registry_credentials.metadata[0].name
        # }
        # The security settings that is specified for a Pod apply to all Containers in the Pod.
        container {
          # image = local.image_tag
          image = var.image_tag
          image_pull_policy = var.image_pull_policy
          name = var.service_name
          security_context {
            run_as_non_root = true
            run_as_user = 1060
            run_as_group = 1060
            read_only_root_filesystem = false
          }
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
          dynamic "readiness_probe" {
            for_each = var.readiness_probe
            content {
              initial_delay_seconds = readiness_probe.value["initial_delay_seconds"]
              period_seconds = readiness_probe.value["period_seconds"]
              timeout_seconds = readiness_probe.value["timeout_seconds"]
              failure_threshold = readiness_probe.value["failure_threshold"]
              success_threshold = readiness_probe.value["success_threshold"]
              dynamic "http_get" {
                for_each = readiness_probe.value.http_get
                content {
                  #host = http_get.value["host"]
                  path = http_get.value["path"]
                  port = http_get.value["port"] != 0 ? http_get.value["port"] : var.service_target_port
                  scheme = http_get.value["scheme"]
                }
              }
            }
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
          # env {
          #   name = "PORT"
          #   value = "8080"
          # }
          dynamic "env" {
            for_each = var.env
            content {
              name = env.key
              value = env.value
            }
          }
          volume_mount {
            name = "configs"
            mount_path = "/etc/rabbitmq"
            read_only = true
          }
          volume_mount {
            name = "erlang-cookie"
            # mount_path = "/var/lib/rabbitmq/mnesia/.erlang.cookie"
            mount_path = "/var/lib/rabbitmq/.erlang.cookie"
            # sub_path = ".erlang.cookie"
            read_only = false
          }
        }
        volume {
          name = "configs"
          config_map {
            name = kubernetes_config_map.config.metadata[0].name
            # Although ConfigMap should be used for non-sensitive configuration data, make the file
            # readable and writable only by the user and group that owns it.
            default_mode = "0400"  # Octal
            items {
              key = "enabled_plugins"
              path = "enabled_plugins"  #File name.
            }
            items {
              key = "rabbitmq.conf"
              path = "rabbitmq.conf"  #File name.
            }
          }
        }
        volume {
          name = "erlang-cookie"
          secret {
            secret_name = kubernetes_secret.secret.metadata[0].name
            default_mode = "0600"  # Octal
            items {
              key = "cookie"
              path = ".erlang.cookie"  #File name.
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
    name = var.dns_name != "" ? var.dns_name : var.service_name
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
      name = "amqp"  # AMQP 0-9-1 and AMQP 1.0 clients.
      port = var.amqp_service_port  # Service port.
      target_port = var.amqp_service_target_port  # Pod port.
      protocol = "TCP"
    }
    port {
      name = "mgmt"  # management UI and HTTP API).
      port = var.mgmt_service_port  # Service port.
      target_port = var.mgmt_service_target_port  # Pod port.
      protocol = "TCP"
    }
    type = var.service_type
  }
}
