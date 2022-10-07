/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable app_name {}
variable image_tag {}
variable namespace {
  default = "default"
}
# Be aware that the default imagePullPolicy depends on the image tag. If a container refers to the
# latest tag (either explicitly or by not specifying the tag at all), imagePullPolicy defaults to
# Always, but if the container refers to any other tag, the policy defaults to IfNotPresent.
#
# When using a tag other that latest, the imagePullPolicy property must be set if changes are made
# to an image without changing the tag. Better yet, always push changes to an image under a new
# tag.
variable imagePullPolicy {
  default = "Always"
}
variable env {
  default = {}
  type = map
}
variable qos_requests_cpu {
  default = ""
}
variable qos_requests_memory {
  default = ""
}
variable qos_limits_cpu {
  default = "0"
}
variable qos_limits_memory {
  default = "0"
}
variable replicas {
  default = 1
  type = number
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
  default = ""
}
variable service_name_master {
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
variable service_session_affinity {
  default = "None"
}
variable http_service_port {
  type = number
}
variable http_service_target_port {
  type = number
}
# variable transport_service_port {
#   type = number
# }
# variable transport_service_target_port {
#   type = number
# }
# The ServiceType allows to specify what kind of Service to use: ClusterIP (default),
# NodePort, LoadBalancer, and ExternalName.
variable service_type {
  default = "ClusterIP"
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
# resource "kubernetes_cluster_role" "cluster_role" {
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
    # The plural form must be used when specifying resources.
    resources = ["endpoints", "services", "namespaces"]
  }
  rule {
    api_groups = ["security.openshift.io"]
    verbs = ["use"]
    resources = ["securitycontextconstraints"]
    resource_names = ["mem-elasticsearch-scc"]
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
    # kind = "ClusterRole"
    kind = "Role"
    # This RoleBinding references the Role specified below...
    # name = kubernetes_cluster_role.cluster_role.metadata[0].name
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

# resource "kubernetes_config_map" "config" {
#   metadata {
#     name = "${var.service_name}-config"
#     namespace = var.namespace
#     labels = {
#       app = var.app_name
#     }
#   }
#   data = {
#     "kibana.yml" = <<EOF
#       server.name: "Kibana"
#       server.port: 5601
#       # https://www.elastic.co/guide/en/kibana/8.4/reporting-settings-kb.html#general-reporting-settings
#       xpack.reporting.enabled: true
#       xpack.monitoring.ui.container.elasticsearch.enabled: true
#       # elasticsearch.url: ["http://mem-elasticsearch.memories:9200"]
#       server.host: "0.0.0.0"
#       EOF
#   }
# }

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
        service_account_name = kubernetes_service_account.service_account.metadata[0].name
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
                    values = ["rs_elasticsearch"]
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
        # Elasticsearch requires vm.max_map_count to be at least 262144. If the OS already sets up
        # this number to a higher value, feel free to remove the init container.
        init_container {
          name = "increase-vm-max-map-count"
          image = "busybox:1.34.1"
          image_pull_policy = "IfNotPresent"
          # Docker (ENTRYPOINT)
          command = ["sysctl", "-w", "vm.max_map_count=262144"]
          security_context {
            # run_as_group = 0
            # run_as_non_root = false
            # run_as_user = 0
            read_only_root_filesystem = true
            privileged = true
          }
        }
        # Increase the max number of open file descriptors.
        init_container {
          name = "increase-fd-ulimit"
          image = "busybox:1.34.1"
          image_pull_policy = "IfNotPresent"
          # Docker (ENTRYPOINT)
          command = ["/bin/sh", "-c", "ulimit -n 65536"]
          security_context {
            # run_as_group = 0
            # run_as_non_root = false
            # run_as_user = 0
            read_only_root_filesystem = true
            privileged = true
          }
        }
        container {
          name = var.service_name
          image = var.image_tag
          image_pull_policy = var.imagePullPolicy
          security_context {
            capabilities {
              drop = ["ALL"]
            }
            run_as_group = 1000
            run_as_non_root = true
            run_as_user = 1000
            read_only_root_filesystem = false
            privileged = false
          }
          # Specifying ports in the pod definition is purely informational. Omitting them has no
          # effect on whether clients can connect to the pod through the port or not. If the
          # container is accepting connections through a port bound to the 0.0.0.0 address, other
          # pods can always connect to it, even if the port isn't listed in the pod spec
          # explicitly. Nonetheless, it is good practice to define the ports explicitly so that
          # everyone using the cluster can quickly see what ports each pod exposes.
          port {
            name = "http"
            container_port = var.http_service_target_port  # The port the app is listening.
            protocol = "TCP"
          }
          # port {
          #   name = "inter-node"
          #   container_port = var.transport_service_target_port  # The port the app is listening.
          #   protocol = "TCP"
          # }
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
          # https://www.elastic.co/guide/en/elasticsearch/reference/current/important-settings.html#node-name
          # By default, Elasticsearch will take the 7 first character of the randomly generated
          # uuid used as the node id. Note that the node id is persisted and does not change when a
          # node restarts and therefore the default node name will also not change.
          env {
            name = "node.name"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          # https://www.elastic.co/guide/en/elasticsearch/reference/current/important-settings.html#network.host
          env {
            name = "network.host"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }
          # When you want to form a cluster with nodes on other hosts, use the static
          # discovery.seed_hosts setting. This setting provides a list of other nodes in the
          # cluster that are master-eligible and likely to be live and contactable to seed the
          # discovery process. Each address can be either an IP address or a hostname that resolves
          # to one or more IP addresses via DNS.
          # https://www.elastic.co/guide/en/elasticsearch/reference/current/important-settings.html#unicast.hosts
          env {
            name = "discovery.seed_hosts"
            value = <<-EOL
              "${var.service_name_master}-0.${var.service_name}.${var.namespace}.svc.cluster.local,
               ${var.service_name_master}-1.${var.service_name}.${var.namespace}.svc.cluster.local,
               ${var.service_name_master}-2.${var.service_name}.${var.namespace}.svc.cluster.local"
            EOL
          }
          # When you start an Elasticsearch cluster for the first time, a cluster bootstrapping step
          # determines the set of master-eligible nodes whose votes are counted in the first election.
          # In development mode, with no discovery settings configured, this step is performed
          # automatically by the nodes themselves.
          #
          # Because auto-bootstrapping is inherently unsafe, when starting a new cluster in production
          # mode, you must explicitly list the master-eligible nodes whose votes should be counted in
          # the very first election.
          # https://www.elastic.co/guide/en/elasticsearch/reference/current/important-settings.html#initial_master_nodes
          # env {
          #   name = "cluster.initial_master_nodes"
          #   value = <<-EOL
          #     "mem-elasticsearch-master-0,
          #      mem-elasticsearch-master-1,
          #      mem-elasticsearch-master-2"
          #   EOL
          # }
          dynamic "env" {
            for_each = var.env
            content {
              name = env.key
              value = env.value
            }
          }
          volume_mount {
            name = "storage"
            mount_path = "/es-data"
          }
        }
        volume {
          name = "storage"
          empty_dir {
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
    selector = {
      pod = kubernetes_deployment.deployment.metadata[0].labels.pod
    }
    session_affinity = var.service_session_affinity
    port {
      name = "http"
      port = var.http_service_port  # Service port.
      target_port = var.http_service_target_port  # Pod port.
      protocol = "TCP"
    }
    type = var.service_type
  }
}
