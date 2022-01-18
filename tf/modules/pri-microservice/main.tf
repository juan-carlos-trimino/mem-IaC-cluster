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
variable "namespace" {
  default = "default"
}
variable "dir_name" {}
variable "cr_login_server" {}
variable "cr_username" {}
variable "cr_password" {}
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
variable "service_port" {
  type = number
  default = 80
}
variable "service_target_port" {
  type = number
  default = 8080
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
  # provisioner "local-exec" {
  #   command = "echo ${var.cr_password} >> pw.txt"
  # }
  provisioner "local-exec" {
    # command = "docker login ${var.cr_login_server} -T -u ${var.cr_username} --password-stdin"
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

/***
Declare a K8s deployment to deploy a microservice; it instantiates the container for the
microservice into the K8s cluster.
***/
resource "kubernetes_deployment" "deployment" {
  depends_on = [
    null_resource.docker_push
  ]
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
        container {
          image = local.image_tag
          name = var.service_name
          # Specifying ports in the pod definition is purely informational. Omitting them has no
          # effect on whether clients can connect to the pod through the port or not. If the
          # container is accepting connections through a port bound to the 0.0.0.0 address, other
          # pods can always connect to it, even if the port isn't listed in the pod spec
          # explicitly. Nonetheless, it is good practice to define the ports explicitly so that
          # everyone using the cluster can quickly see what ports each pod exposes.
          # port {
          #   name = "http"
          #   container_port = 8080  # The port the container (app) is listening.
          #   protocol = "TCP"
          # }
          # port {
          #   name = "https"
          #   container_port = 8443  # The port the container (app) is listening.
          #   protocol = "TCP"
          # }
          port {
            container_port = var.service_target_port  # The port the app is listening.
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
          env {
            name = "PORT"
            value = "8080"
          }
          dynamic "env" {
            for_each = var.env
            content {
              name = env.key
              value = env.value
            }
          }
        }
        #
        image_pull_secrets {
          name = kubernetes_secret.registry_credentials.metadata[0].name
        }
      }
    }
  }
}

/***
Declare a K8s service to create a DNS record to make the microservice accessible within the cluster.
***/
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
      port = var.service_port  # Service port.
      target_port = var.service_target_port  # Pod port.
    }
    # port {
    #   name = "http"
    #   port = 80  # Service port.
    #   target_port = "http"  # Pod port.
    # }
    # port {
    #   name = "https"
    #   port = 443
    #   target_port = "https"
    # }
    type = var.service_type
  }
}
