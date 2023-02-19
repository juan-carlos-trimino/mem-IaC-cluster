/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable app_name {
  type = string
}
variable image_tag {
  type = string
}
variable namespace {
  default = "default"
  type = string
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
  type = string
}
variable qos_requests_cpu {
  default = ""
  type = string
}
variable qos_requests_memory {
  default = ""
  type = string
}
variable qos_limits_cpu {
  default = "0"
  type = string
}
variable qos_limits_memory {
  default = "0"
  type = string
}
variable replicas {
  default = 1
  type = number
}
variable es_hosts {
  type = string
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
  type = string
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
variable service_session_affinity {
  default = "None"
  type = string
}
variable beats_service_port {
  type = number
}
variable beats_service_target_port {
  type = number
}
variable logstash_service_port {
  type = number
}
variable logstash_service_target_port {
  type = number
}
# The ServiceType allows to specify what kind of Service to use: ClusterIP (default),
# NodePort, LoadBalancer, and ExternalName.
variable service_type {
  default = "ClusterIP"
  type = string
}

/***
Define local variables.
***/
locals {
  pod_selector_label = "rs-${var.service_name}"
  svc_selector_label = "svc-${var.service_name}"
  ls_label = "logstash"
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
    # Settings and configuration options for Logstash are defined in the logstash.yml configuration
    # file. A full list of supported settings can be found in the reference guide:
    # https://www.elastic.co/guide/en/logstash/8.6/logstash-settings-file.html
    # (1) Define the network address on which Logstash will listen; 0.0.0.0 denotes that it needs
    #     to listen on all available interfaces.
    "logstash.yml" = <<EOF
      http:
        host: "0.0.0.0"
      path:
        # The path to the Logstash config for the main pipeline.
        config: /usr/share/logstash/pipeline
      pipeline:
        # Define the maximum number of events the filter and output plugins will accept each time
        # they run.
        batch:
          size: 125  # Events per batch per worker thread used by the pipeline.
          # Determine how long Logstash will wait to collect a full batch of events before
          # dispatching it for processing. If there are not enough events in the queue, a smaller
          # batch will be dispatched once the delay time period is passed.
          delay: 50  # In milliseconds.
      queue:
        # Determine the type of queue used by Logstash.
        type: "memory"
      EOF
    # Any Logstash configuration must contain at least one input plugin and one output plugin.
    # Filters are optional.
    "logstash-pipeline.conf" = <<EOF
      input {
        # From where is the data coming.
        beats {
          port => 5044
          ssl => false
        }
      }
      filter {
        # Container logs are received with a variable named index_prefix;
        # since it is in json format, we can decode it via json filter plugin.
        # if [index_prefix][memories] {
        #   grok {
        #     match => { "message" => "%%{TIMESTAMP_ISO8601:timestamp} %%{LOGLEVEL:level} %%{GREEDYDATA:message}" }
        #   }
        #   # if [message] =~ "/^\{.*\}$/" {
        #   # # if [message] =~ "\A\{.+\}\z" {
            # json {
            #   source => "message"
            #   # skip_on_invalid_json => false
            # }
        #   # }
        #   # To parse JSON log lines in Logstash that were sent from Filebeat you need to use a json filter instead of a codec. This is because Filebeat sends its data as JSON and the contents of your log line are contained in the message field.
        #   # json {
        #   #   source => "message"
        #   #   skip_on_invalid_json => false
        #   # }
        # }
        mutate {
          add_field => { "description" => "From memories!!!999" }
          # @metadata is not exposed outside of Logstash by default.
          # add_field => { "[@metadata][index_prefix]" => "%%{index_prefix}-%%{+YYYY.MM.dd}" }
          # We added the index_prefix field to the metadata, and we no longer need the field. Do
          # not expose the index_prefix field to Kibana.
          # remove_field => ["index_prefix"]
          remove_field => ["agent", "stream", "input", "host", "tags", "ecs"]
        }
      }
      output {
        elasticsearch {
          hosts => ["${var.es_hosts}"]
          index => "%%{[@metadata][beat]}-%%{[@metadata][version]}-%%{+YYYY.MM.dd}"
          template_overwrite => false
          manage_template => false
          ssl => false
        }
        # Send events to the standard output interface; the events are visible in the terminal
        # running Logstash.
        stdout {
          codec => rubydebug  # Help show the structure.
        }
      }
      EOF
  }
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
        pod_selector_lbl = local.pod_selector_label
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
          pod_selector_lbl = local.pod_selector_label
          # It must match the label selector of the Service.
          svc_selector_lbl = local.svc_selector_label
          ls_lbl = local.ls_label
        }
      }
      #
      spec {
        termination_grace_period_seconds = var.termination_grace_period_seconds
        security_context {
          fs_group = 1000
        }
        container {
          name = var.service_name
          image = var.image_tag
          image_pull_policy = var.image_pull_policy
          security_context {
            capabilities {
              drop = ["ALL"]
            }
            run_as_non_root = true
            run_as_user = 1000
            run_as_group = 1000
          }
          # Specifying ports in the pod definition is purely informational. Omitting them has no
          # effect on whether clients can connect to the pod through the port or not. If the
          # container is accepting connections through a port bound to the 0.0.0.0 address, other
          # pods can always connect to it, even if the port isn't listed in the pod spec
          # explicitly. Nonetheless, it is good practice to define the ports explicitly so that
          # everyone using the cluster can quickly see what ports each pod exposes.
          port {
            container_port = var.beats_service_target_port  # The port the app is listening.
            protocol = "TCP"
          }
          port {
            container_port = var.logstash_service_target_port  # The port the app is listening.
            protocol = "TCP"
          }
          resources {
            requests = {
              # If a Container specifies its own memory limit, but does not specify a memory
              # request, Kubernetes automatically assigns a memory request that matches the limit.
              # Similarly, if a Container specifies its own CPU limit, but does not specify a CPU
              # request, Kubernetes automatically assigns a CPU request that matches the limit.
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
          volume_mount {
            name = "logstash"
            mount_path = "/usr/share/logstash/config"
            # read_only = true
          }
          volume_mount {
            name = "config"
            # The directory that Logstash reads configurations from by default.
            mount_path = "/usr/share/logstash/pipeline"
            # read_only = true
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.config.metadata[0].name
            # Although ConfigMap should be used for non-sensitive configuration data, make the file
            # readable and writable only by the user and group that owns it.
            default_mode = "0600"  # Octal
            items {
              key = "logstash-pipeline.conf"
              path = "logstash-pipeline.conf"  #File name.
            }
          }
        }
        volume {
          name = "logstash"
          config_map {
            name = kubernetes_config_map.config.metadata[0].name
            default_mode = "0600"  # Octal
            items {
              key = "logstash.yml"
              path = "logstash.yml"  #File name.
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
      svc_selector_lbl = local.svc_selector_label
    }
    session_affinity = var.service_session_affinity
    port {
      name = "beat"
      port = var.beats_service_port  # Service port.
      target_port = var.beats_service_target_port  # Pod port.
      protocol = "TCP"
    }
    # Logstash Monitoring API.
    port {
      name = "logstash"
      port = var.logstash_service_port  # Service port.
      target_port = var.logstash_service_target_port  # Pod port.
      protocol = "TCP"
    }
    type = var.service_type
  }
}
