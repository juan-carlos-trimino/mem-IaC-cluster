/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "app_name" {}
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
variable "replicas" {
  default = 1
  type = number
}
variable "revision_history_limit" {
  default = 2
  type = number
}
variable "termination_grace_period_seconds" {
  default = 30
  type = number
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

resource "kubernetes_config_map" "config" {
  metadata {
    name = "${var.service_name}-config"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  data = {
    # (1) Define the network address on which Logstash will listen; 0.0.0.0 denotes that it needs
    #     to listen on all available interfaces.
    # (2) Specify where Logstash will find its configuration file. This configuration path is where
    #     'logstash.conf' resides; this file is what instructs Logstash about how to parse the
    #     incoming log files.
    "logstash.yml" = <<EOF
      http.host: 0.0.0.0
      path.config: /usr/share/logstash/pipeline
      EOF
    "logstash.conf" = <<EOF
      # All input will come from Filebeat, no local logs.
      input {
        beats {
          port => 5044
        }
      }
      filter {
        # grok {
        #  match => {"message" => "%%{COMBINEDAPACHELOG}"}
        # }
        # date {
        #  match => ["timestamp", "dd/MMM/yyyy:HH:mm:ss Z"]
        # }
        # Container logs are received with a variable named index_prefix.
        # Since it is in JSON format, decode it via the JSON filter plugin.
        if [index_prefix] == "k8s-logs" {
          if [message] =~ /^\{.*\}$/ {
            json {
              source => "message"
              skip_on_invalid_json => true
            }
          }
        }
        #
        # Do not expose the index_prefix field to Kibana.
        mutate {
          # @metadata is not exposed outside of Logstash by default.
          add_field => { "[@metadata][index_prefix]" => "%%{index_prefix}-%%{+YYYY.MM.dd}" }
          # Since index_prefix was added to metadata, the ["index_prefix"] field is no longer needed.
          remove_field => ["index_prefix"]
        }
        #
        if [ClientHost] {
          geoip {
            source => "ClientHost"
          }
        }
        # geoip {
        #   source => "clientip"
        # }
      }
      output {
        elasticsearch {
          hosts => ["mem-elasticsearch:9200"]
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
    revision_history_limit = var.revision_history_limit
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
          name = var.service_name
          image = var.image_tag
          image_pull_policy = var.imagePullPolicy
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
