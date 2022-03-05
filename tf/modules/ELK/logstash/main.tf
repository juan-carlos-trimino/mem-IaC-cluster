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
variable "service_session_affinity" {
  default = "None"
}
variable "service_port" {
  type = number
}
variable "service_target_port" {
  type = number
}
variable "dns_name" {
  default = ""
}
# The ServiceType allows to specify what kind of Service to use: ClusterIP (default),
# NodePort, LoadBalancer, and ExternalName.
variable "service_type" {
  default = "ClusterIP"
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
    # logstash.yml
    # (1) It defines the network address on which Logstash will listen; 0.0.0.0 to denote that it
    #     needs to listen on all available interfaces.
    # (2) It specifies where Logstash should find its configuration file which is /usr/share/logstash/pipeline.
    # This configuration path is where the second file (logstash.conf) resides. That second file is what instructs Logstash about how to parse the incoming log files. Let’s have a look at the interesting parts of this file:
    "logstash.yml" = <<EOF
      http.host: 0.0.0.0
      path.config: /usr/share/logstash/pipeline
      EOF
    # The input stanza instructs Logstash as to where it should get its data. The daemon will be listening at port 5044 and an agent (Filebeat in our case) will push logs to this port.
    # The filter stanza is where we specify how logs should be interpreted. Logstash uses filters to parse and transform log files to a format understandable by Elasticsearch. In our example, we are using grok. Explaining how the Grok filter works is beyond the scope of this article but you can read more about it here. We are using one of the options available for Grok out of the box, which is used for parsing Apache logs in the combined format (COMBINEDAPACHELOG). Since it’s a popular log format, grok can automatically extract key information from each line and convert it to JSON format.
    # The date stanza is used for adding a timestamp to each logline. You can use the timestamp to configure exactly how the timestamp would appear.
    # The geoip part is used to add the client’s IP address to the log so that we know where it is coming from.
    # The output part defines the target, where Logstash should forward the parsed log data. In our lab, we want Logstash to forward it to the Elasticsearch cluster. We specify the service name without the need to add the namespace and the rest of the URL (like in elasticsearch-logging.kube-system.svc.cluster.local) because both resources are in the same namespace.
    "logstash.conf" = <<EOF
      input {
        beats {
          port => 5044
        }
      }
      filter {
        grok {
          match => {"message" => "%%{COMBINEDAPACHELOG}"}
        }
        date {
          match => ["timestamp", "dd/MMM/yyyy:HH:mm:ss Z"]
        }
        geoip {
          source => "clientip"
        }
      }
      output {
        elasticsearch {
          hosts => ["elasticsearch-logging:9200"]
        }
      }
      EOF
  }
}


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
          volume_mount {
            name = "config1"
            mount_path = "/usr/share/logstash/config"
            read_only = true
          }
          volume_mount {
            name = "config2"
            mount_path = "/usr/share/logstash/pipeline"
            read_only = true
          }
        }
        volume {
          name = "config1"
          config_map {
            name = kubernetes_config_map.config.metadata[0].name
            # Although ConfigMap should be used for non-sensitive configuration data, make the file
            # readable and writable only by the user and group that owns it.
            default_mode = "0400"  # Octal
            items {
              key = "logstash.yml"
              path = "logstash.yml"  #File name.
            }
          }
        }
        volume {
          name = "config2"
          config_map {
            name = kubernetes_config_map.config.metadata[0].name
            # Although ConfigMap should be used for non-sensitive configuration data, make the file
            # readable and writable only by the user and group that owns it.
            default_mode = "0400"  # Octal
            items {
              key = "logstash.conf"
              path = "logstash.conf"  #File name.
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
      name = "logstash"
      port = var.service_port  # Service port.
      target_port = var.service_target_port  # Pod port.
      protocol = "TCP"
    }
    type = var.service_type
  }
}
