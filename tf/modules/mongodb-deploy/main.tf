/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "app_name" {}
variable "app_version" {}
variable "image_tag" {}
variable "namespace" {
  default = "default"
}
variable "dns_name" {
  default = ""
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
variable "terminationGracePeriodSeconds" {
  default = 30
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
  default = "1Gi"
}
variable "service_name" {
  default = ""
}
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
}
variable "service_target_port" {
  type = number
}

# Because PersistentVolumeClaim (PVC) can only be created in a specific namespace, they can only be
# used by pods in the same namespace.
resource "kubernetes_persistent_volume_claim" "mongodb_claim" {
  metadata {
    name = var.pvc_name
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  spec {
    # Empty string must be explicitly set otherwise default StorageClass will be set.
    # -------------------------------------------------------------------------------
    # StorageClass enables dynamic provisioning of PersistentVolumes (PV).
    # (1) When creating a claim, the PV is created by the provisioner referenced in the
    #     StorageClass resource; the provisioner is used even if an existing manually
    #     provisioned PV matches the PVC.
    # (2) The default storage class is used to dynamically provision a PV if the PVC does not
    #     explicitly state which storage class name to use.
    # (3) To bind the PVC to a pre-provisioned PV instead of dynamically provisioning a new one,
    #     specify an empty string as the storage class name; effectively disable dynamic
    #     provisioning.
    storage_class_name = var.pvc_storage_class_name
    access_modes = var.pvc_access_modes
    resources {
      requests = {
        storage = var.pvc_storage_size
      }
    }
  }
}

# Declare a K8s deployment to deploy a microservice; it instantiates the container for the
# microservice into the K8s cluster.
resource "kubernetes_deployment" "deployment" {
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
        termination_grace_period_seconds = var.termination_grace_period_seconds
        container {
          image = var.image_tag
          image_pull_policy = var.imagePullPolicy
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
          dynamic "env" {
            for_each = var.env
            content {
              name = env.key
              value = env.value
            }
          }
          # Mounting an individual ConfigMap entry as a file without hiding other files in the
          # directory.
          # *** emptyDir ***
          # The simplest volume type, emptyDir. is an empty directory used for storing transient
          # data. It is useful for sharing files between containers running on the same pod, or for
          # a single container to write temporary data to disk. Since the lifetime of the volume is
          # tied to the pod, the volume’s contents are lost when the pod is deleted.
          # volume_mount {
          #   name = "mongodb-storage"
          #   mount_path = "/data/db"
          #   read_only = false
          # }
          # *** emptyDir ***
          # *** Mount external storage in a volume to persist pod data across pod restarts ***
          volume_mount {
            name = "mongodb-storage"
            mount_path = "/data/db"  #"$(DATA_FILE_PATH)"   "/aaa/data/db"     #"$(mongodb.conf.storage.dbPath)"    
          }
          # *** Mount external storage in a volume to persist pod data across pod restarts ***
        }
        # *** emptyDir ***
        # volume {
        #   name = "mongodb-storage"
        #   empty_dir {
        #   }
        # }
        # *** emptyDir ***
        # *** Mount external storage in a volume to persist pod data across pod restarts ***
        volume {
          name = "mongodb-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.mongodb_claim.metadata[0].name
          }
        }
        # *** Mount external storage in a volume to persist pod data across pod restarts ***
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
      port = var.service_port  # Service port.
      target_port = var.service_target_port  # Pod port.
    }
    type = var.service_type
  }
}
