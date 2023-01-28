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
variable elasticsearch_hosts {
  type = string
}
variable kibana_host {
  type = string
}
variable util_path {
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
# Containers in a pod usually run under separate Linux namespaces, which isolate their processes
# from processes running in other containers or in the node's default namespace. Certain pods
# (usually system pods) need to operate in the host's default namespace, allowing them to see and
# manipulate node-level resources and devices. If a pod needs to use the node's network adapters
# instead of its own virtual network adapters, set the hostNetwork property to true. In doing so,
# the pod gets to use the node's network interfaces instead of its own; this means the pod doesn't
# get its own IP address, and if it runs a process that binds to a port, the process will be bound
# to the node's port. (It allows a pod to listen to all network traffic for all pods on the node
# and communicate with other pods on the network namespace.)
# $ kubectl exec <pod-name> -n <namespace> -- ifconfig
variable host_network {
  default = false
  type = bool
}

variable env {
  default = {}
  type = map
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
variable revision_history_limit {
  default = 2
  type = number
}
# The termination grace period defaults to 30, which means the pod's containers will be given 30
# seconds to terminate gracefully before they're killed forcibly.
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
variable dns_name {
  default = ""
  type = string
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
  pod_selector_label = "ps-${var.service_name}"
  fb_label = "filebeat"
}

resource "null_resource" "scc-filebeat" {
  provisioner "local-exec" {
    # command = "oc apply -f ${file("${var.util_path}/mem-filebeat-scc.yaml")}"
    command = "oc apply -f ./modules/elk/filebeat/util/mem-filebeat-scc.yaml"
  }
  #
  provisioner "local-exec" {
    when = destroy
    command = "oc delete scc mem-filebeat-scc"
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
      # "kubernetes.io/enforce-mountable-secrets" = true
  #   }
  }
  # secret {
  #   name = kubernetes_secret.rabbitmq_secret.metadata[0].name
  # }
}

# Roles define WHAT can be done; role bindings define WHO can do it.
# The distinction between a Role/RoleBinding and a ClusterRole/ClusterRoleBinding is that the Role/
# RoleBinding is a namespaced resource; ClusterRole/ClusterRoleBinding is a cluster-level resource.
# A Role resource defines what actions can be taken on which resources; i.e., which types of HTTP
# requests can be performed on which RESTful resources.
resource "kubernetes_cluster_role" "cluster_role" {
  metadata {
    name = "${var.service_name}-cluster-role"
    labels = {
      app = var.app_name
    }
  }
  rule {
    # The core apiGroup, which has no name - hence the "".
    api_groups = [""]
    verbs = ["get", "watch", "list"]
    # The plural form must be used when specifying resources.
    resources = ["pods", "namespaces", "nodes"]
  }
  rule {
    api_groups = ["security.openshift.io"]
    verbs = ["use"]
    resources = ["securitycontextconstraints"]
    resource_names = ["mem-filebeat-scc"]
  }
}

# Bind the role to the service account.
# Note: If you are binding a ClusterRole that grants access to cluster-level resources (which is
# what Security Context Constraints are), you need to use a ClusterRoleBinding instead of a
# (namespaced) RoleBinding.
resource "kubernetes_cluster_role_binding" "cluster_role_binding" {
  metadata {
    name = "${var.service_name}-cluster-role-binding"
    labels = {
      app = var.app_name
    }
  }
  # A RoleBinding always references a single Role, but it can bind the Role to multiple subjects.
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "ClusterRole"
    # This RoleBinding references the Role specified below...
    name = kubernetes_cluster_role.cluster_role.metadata[0].name
  }
  # ... and binds it to the specified ServiceAccount in the specified namespace.
  subject {
    # The default permissions for a ServiceAccount don't allow it to list or modify any resources.
    kind = "ServiceAccount"
    name = kubernetes_service_account.service_account.metadata[0].name
    namespace = kubernetes_service_account.service_account.metadata[0].namespace
  }
}

resource "kubernetes_config_map" "config_files" {
  metadata {
    name = "${var.service_name}-config-files"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  data = {
    "memories-fields.yml" = <<EOF
      - key: filebeat-memories
        title: filebeat-memories
        date_detection: true
        description: "These are the fields generated by the memories app for logging."
        fields:
          - name: "app"
            type: "text"
            index: true
            analyzer: "english"
            norms: false
            required: true
          - name: "level"
            type: "text"
            index: true
            analyzer: "english"
            norms: false
            required: true
          - name: "message"
            type: "text"
            index: true
            analyzer: "english"
            norms: false
            required: true
          - name: "msgId"
            type: "text"
            index: true
            analyzer: "english"
            norms: false
            required: true
          - name: "service"
            type: "text"
            index: true
            analyzer: "english"
            norms: false
            required: true
          - name: "@timestamp"
            type: "date"
            # format: "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            ignore_malformed: true
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-date-format.html
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/date.html#multiple-date-formats
            # format: "YYYY-MM-ddTHH:mm:ss.SSSSS||strict_date_optional_time||epoch_millis"
            # format: "2023-01-10T20:15:25.000+00:00"
            # index: true
            required: true
      EOF
    # "filebeat.yml" = "${file("${var.util_path}/filebeat.yml")}"
    # To see a full example of the configuration file, go to https://www.elastic.co/guide/en/beats/filebeat/current/filebeat-reference-yml.html
    # The Filebeat configuration file consists, mainly, of the following sections. For some more information on how to configure Filebeat(https://www.elastic.co/guide/en/beats/filebeat/current/configuring-howto-filebeat.html).
    "filebeat.yml" = <<EOF
      # (1) The Modules configuration section can help with the collection, parsing, and visualization of common log formats (optional).
      # (2) The Inputs section determines the input sources (mandatory if not using Module configuration). If you are not using modules, you need to configure the Filebeat manually.
      # To configure inputs:
      #   https://www.elastic.co/guide/en/beats/filebeat/current/configuration-filebeat-options.html
      # Inputs specify how Filebeat locates and processes input data.
      # https://www.elastic.co/guide/en/beats/filebeat/current/filebeat-reference-yml.html
      filebeat.inputs:
        # Use the container input to read containers log files.
        - type: "container"
          # Change to true to enable this input configuration.
          enabled: true
          # Read from the specified streams only: all (default), stdout or stderr.
          stream: "all"
          # Use the given format when reading the log file: auto, docker or cri. The default is
          # auto; it will automatically detect the format.
          format: "auto"
          # The plain encoding is special because it does not validate or transform any input.
          # encoding: "utf-8"
          encoding: "plain"
          # The symlinks option allows Filebeat to harvest symlinks in addition to regular files.
          # symlinks: true
          # You must set ignore_older to be greater than close_inactive.
          ignore_older: "72h"
          close_inactive: "48h"
          scan_frequency: "10s"
          json:
            # message_key: "message"
            keys_under_root: true
            overwrite_keys: true
            add_error_key: true
            # ignore_decoding_error: true
          # include_lines: ["^{"]
          # To collect container logs, each Filebeat instance needs access to the local log's path,
          # which is actually a log directory mounted from the host. With this configuration,
          # Filebeat can collect logs from all the files that exist under the /var/log/containers/
          # directory.
          paths: ["/var/log/containers/*.log"]
          # Optional fields that you can specify to add additional information to the output.
          # fields:
          #   index_prefix: ["memories-filebeat"]
          # If this option is set to true, the custom fields are stored as top-level fields in the
          # output document instead of being grouped under a fields sub-dictionary.
          fields_under_root: true
          # If present, this formatted string overrides the index for events from this input (for
          # elasticsearch outputs), or sets the raw_index field of the event's metadata (for other outputs).
          # index: "%%{[agent.name]}-%%{[fields.index_prefix]}-%%{[agent.version]}-%%{+yyyy.MM.dd}"
          # By default, all events contain host.name. This option can be set to true to disable the
          # addition of this field to all events.
          publisher_pipeline.disable_host: false
          processors:
            # - decode_json_fields:
            #     fields: ["message", "app", "msgId", "timestamp", "service", "level"]
            #     process_array: false
            #     max_depth: 1
            #     target: "json"
            #     overwrite_keys: true
            #     add_error_key: true
            # - drop_fields:
            #     fields: ["message"]
            # Set each event with host metadata.
            # - add_host_metadata: ~
            - add_kubernetes_metadata:
                in_cluster: true
                host: $(NODE_NAME)
                default_matchers.enabled: false
                matchers:
                  - logs_path:
                      logs_path: "/var/log/containers/"
      # (3) The Processors section is used to configure processing across data exported by Filebeat
      # (optional). You can define a processor (https://coralogix.com/blog/filebeat-configuration-best-practices-tutorial/) at the top-level in the configuration; the processor
      # is applied to all data collected by Filebeat. Furthermore, you can define a processor under
      # a specific input; the processor is applied to the data collected for that input. For a list
      # of type of processors, go to https://www.elastic.co/guide/en/beats/filebeat/current/defining-processors.html#processors
      # processors:
      #   # https://www.elastic.co/guide/en/beats/filebeat/current/processor-timestamp.html
        # - timestamp:
        #     field: "timestamp"
        #     target_field: "mem-timestamp"
        #     ignore_missing: true
        #     ignore_failure: true
        #     timezone: "Europe/London"
        #     layouts:
        #       - "2006-01-02T15:04:05.00000"
      #         # - "RFC850"
      #         # - "RFC1123"
      #         # - "RFC1123Z"
      #         # - "RFC3339"
      #         # - "RFC3339Nano"
        # - drop_fields:
        #     fields: ["timestamp"]
      # (4) The Output section determines the output destination of the processed data.
      # ========================================= Outputs =========================================
      # Configure what output to use when sending the data collected by the beat. Only a single
      # output may be defined.
      # See https://www.elastic.co/guide/en/beats/filebeat/current/configuring-output.html
      # output.logstash:
      #   enabled: true
      #   protocol: "http"
      #   # The Logstash hosts.
      #   hosts: ["mem-logstash.memories.svc.cluster.local:5044"]
      #   ssl.enabled: false
      #   # Number of workers per Logstash host.
      #   worker: 4
      #   loadbalance: false
      #   ttl: 0
      #   pipelining: 2

      # https://www.elastic.co/guide/en/beats/filebeat/current/elasticsearch-output.html
      output.elasticsearch:
        enabled: true
        allow_older_versions: true
        # To enable SSL, add https to all URLs defined under hosts.
        hosts: ["${var.elasticsearch_hosts}"]
        # It is recommended to include agent.version in the name to avoid mapping issues when you upgrade.
        index: "filebeat-%%{[agent.version]}-memories-%%{+yyyy.MM.dd}"
        # index: "memories-filebeat-%%{[agent.version]}-%%{+yyyy.MM.dd}"
        # non_indexable_policy.dead_letter_index:
        #   index: "memories-dead-letter-index"
        worker: 1
        ssl:
          enabled: false
      setup:
        # Index Lifecycle Management (ILM).
        # If ILM is enabled (which is typically the default), setup.template.name and setup.template.pattern are ignored.
        # https://www.elastic.co/guide/en/beats/filebeat/current/ilm.html
        ilm:
          enabled: false
          # overwrite: true
          # policy_name: "memories"
          # rollover_alias: "filebeat-%%{[agent.version]}-memories-%%{+yyyy.MM.dd}"
          # patern: "{now/d}-000001"
        # https://www.elastic.co/guide/en/beats/filebeat/current/filebeat-template.html#filebeat-template
        # https://www.elastic.co/guide/en/elasticsearch/reference/current/index-templates.html
        template:
          enabled: true
          # path: "filebeat.template.json"
          # name: "memories-filebeat-%%{[agent.version]}"
          name: "filebeat-%%{[agent.version]}-memories"
          # pattern: "memories-filebeat-%%{[agent.version]}-*"
          pattern: "filebeat-%%{[agent.version]}-*"
          overwrite: true
          fields: "/etc/memories-fields.yml"
          # append_fields:
          #   - name: timestamp
          #     type: date
          # settings:
          #   index.number_of_shards: 1
          #   index.number_of_replicas: 2
        # See https://www.elastic.co/guide/en/beats/filebeat/current/setup-kibana-endpoint.html
        kibana:
          # enabled: true
          host: "${var.kibana_host}"
          path: "/kibana"
          ssl:
            enabled: false
        # dashboards:
        #   enabled: true
        #   beat: "filebeat"
          # index: "%%{[fields.index_prefix]}-%%{[agent.version]}-%%{+yyyy.MM.dd}"
          # index: "memories-%%{[agent.name]}-%%{[agent.version]}-*"
          # kibana_index: ".kibana-memories"
      EOF
  }
}

# Deploy Filebeat as a DaemonSet to ensure there's a running instance on each node of the cluster;
# Filebeat will retrieve and ship the container logs. The Docker logs host folder
# (/var/lib/docker/containers) is mounted on the Filebeat container. Filebeat starts an input for
# the files and begins harvesting them as soon as they appear in the folder.
# $ kubectl get ds -n memories
resource "kubernetes_daemonset" "daemonset" {
  metadata {
    name = var.service_name
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
    # For OpenShift only!!!
    # Override the default node selector for the kube-system namespace (or your custom namespace)
    # to allow for scheduling on any node. This command sets the node selector for the project to
    # an empty string. If you don't run this command, the default node selector will skip master
    # nodes.
    annotations = {
      "openshift.io/node-selector" = ""
    }
  }
  #
  spec {
    selector {
      match_labels = {
        # It must match the labels in the Pod template (.spec.template.metadata.labels).
        pod_selector_lbl = local.pod_selector_label
      }
    }
    # Pod template.
    template {
      metadata {
        labels = {
          app = var.app_name
          # It must match the labels in the Pod template (.spec.template.metadata.labels).
          pod_selector_lbl = local.pod_selector_label
          fb_lbl = local.fb_label
        }
      }
      #
      spec {
        service_account_name = kubernetes_service_account.service_account.metadata[0].name
        termination_grace_period_seconds = var.termination_grace_period_seconds
        host_network = var.host_network
        # For Pods running with hostNetwork, you should explicitly set its DNS policy to
        # "ClusterFirstWithHostNet". Otherwise, Pods running with hostNetwork and "ClusterFirst"
        # will fallback to the behavior of the "Default" policy.
        dns_policy = "ClusterFirstWithHostNet"
        container {
          name = var.service_name
          image = var.image_tag
          image_pull_policy = var.image_pull_policy
          security_context {
            run_as_non_root = false
            run_as_user = 0
            # By setting this property to true, the app will not be allowed to write to /tmp, and
            # the error below will be generated. To avoid the error, mount a volume to the /tmp
            # directory.
            read_only_root_filesystem = false   # jct
            # Filebeat needs extra configuration to run in the Openshift environment; enable the
            # container to be privileged as an administrator for Openshift.
            # (filebeat pods enter in CrashLoopBackOff status, and the following error appears:
            #  Exiting: Failed to create Beat meta file: open
            #  /usr/share/filebeat/data/meta.json.new: permission denied
            privileged = true
          }
          # Docker (CMD).
          # -c -> Specify the configuration file to use for Filebeat.
          # -e => Log to stderr and disables syslog/file output.
          # Location of our filebeat.yml file; MUST MATCH the mount_path in the volume_mount of
          # "config."
          args = ["-c", "/etc/filebeat.yml", "-e"]
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
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
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

          volume_mount {
            name = "config"
            mount_path = "/etc/filebeat.yml"
            sub_path = "filebeat.yml"
            read_only = true
          }

          volume_mount {
            name = "memories-fields"
            mount_path = "/etc/memories-fields.yml"
            sub_path = "memories-fields.yml"
            read_only = true
          }

          volume_mount {
            name = "data"
            mount_path = "/usr/share/filebeat/data"  # Directory location on host.
            read_only = false
          }
          # /var/lib/docker/containers is one of a few filesystems that Filebeat will have access.
          # Notice that the volume type of this path is hostPath, which means that Filebeat will
          # have access to this path on the node rather than the container. Kubernetes uses this
          # path on the node to write data about the containers, additionally, any STDOUT or STDERR
          # coming from the containers running on the node is directed to this path in JSON format
          # (the standard output and standard error data is still viewable through the kubectl logs
          # command, but a copy is kept at this path).
          volume_mount {
            name = "varlibdockercontainers"
            mount_path = "/var/log/containers/"
            read_only = true
          }
          volume_mount {
            name = "varlog"
            mount_path = "/var/log"
            read_only = true
          }
          # See read_only_root_filesystem.
          # volume_mount {
          #   name = "tmp"
          #   mount_path = "/tmp"
          #   read_only = false
          # }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.config_files.metadata[0].name
            default_mode = "0600"
            # items {
            #   key = "filebeat.yml"
            #   path = "filebeat.yml"  # File name.
            # }
          }
        }

        volume {
          name = "memories-fields"
          config_map {
            name = kubernetes_config_map.config_files.metadata[0].name
            default_mode = "0600"
            # items {
            #   key = "filebeat.yml"
            #   path = "filebeat.yml"  # File name.
            # }
          }
        }



        # The data folder stores a registry of read status for all files so that Filebeat doesn't
        # send everything again on a pod restart.
        volume {
          name = "data"
          host_path {
            # When Filebeat runs as non-root user, this directory needs to be writable by group
            # (g+w).
            path = "/var/lib/filebeat-data"
            type = "DirectoryOrCreate"
          }
        }
        volume {
          name = "varlibdockercontainers"
          # A hostPath volume points to a specific file or directory on the node's filesystem. Pods
          # running on the same node and using the same path in their hostPath volume see the same
          # files.
          host_path {
            # Access the node's /var/lib/docker/containers.
            path = "/var/log/containers/"  # Directory location on host.
          }
        }
        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }
        # volume {
        #   name = "tmp"
        #   host_path {
        #     path = "/tmp"
        #   }
        # }
      }
    }
  }
}
