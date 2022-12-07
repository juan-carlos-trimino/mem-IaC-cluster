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
# When using a tag other than latest, the imagePullPolicy property must be set if changes are made
# to an image without changing the tag. Better yet, always push changes to an image under a new
# tag.
variable imagePullPolicy {
  default = "Always"
}
variable env {
  default = {}
  type = map
}
variable path_to_config {
  type = string
}
variable es_cluster_name {
  type = string
}
variable es_username {
  type = string
  sensitive = true
}
variable es_password {
  type = string
  sensitive = true
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
variable revision_history_limit {
  default = 2
  type = number
}
# The termination grace period defaults to 30, which means the pod's containers will be given 30
# seconds to terminate gracefully before they're killed forcibly. The StatefulSet should not
# specify a termination grace period of 0.
variable termination_grace_period_seconds {
  default = 30
  type = number
}
# See https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#orderedready-pod-management
variable pod_management_policy {
  default = "OrderedReady"
}
# The primary use case for setting this field is to use a StatefulSet's Headless Service to
# propagate SRV records for its Pods without respect to their readiness for purpose of peer
# discovery.
variable publish_not_ready_addresses {
  default = false
  type = bool
}
variable pvc_access_modes {
  default = []
  type = list
}
variable pvc_storage_class_name {
  default = ""
}
variable pvc_storage_size {
  default = "5Gi"
}
variable service_name {
  default = ""
}
variable service_name_headless {
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
variable transport_service_port {
  type = number
}
variable transport_service_target_port {
  type = number
}
# The ServiceType allows to specify what kind of Service to use: ClusterIP (default),
# NodePort, LoadBalancer, and ExternalName.
variable service_type {
  default = "ClusterIP"
}

/***
Define local variables.
***/
locals {
  pod_selector_label = "ps-${var.service_name}"
  svc_label = "svc-${var.service_name_headless}"
  es_label = "es-cluster"
}

resource "null_resource" "scc-elasticsearch" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "oc apply -f ./modules/elk/elasticsearch/util/mem-elasticsearch-scc.yaml"
  }
  provisioner "local-exec" {
    when = destroy
    command = "oc delete scc mem-elasticsearch-scc"
  }
}

resource "kubernetes_secret" "secret" {
  metadata {
    name = "${var.service_name}-secret"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  # Plain-text data.
  data = {
    es_username = var.es_username
    es_password = var.es_password
  }
  type = "Opaque"
}




resource "kubernetes_config_map" "es_config" {
  metadata {
    name = "${var.service_name}-config"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  data = {
    # ======================== Elasticsearch Configuration ========================
    # ---------------------------------- Cluster ----------------------------------
    # Cluster name identifies the cluster for auto-discovery. If you're running multiple clusters on
    # the same network, make sure you use unique names.
    "cluster.name": "cluster-elk"
    # ------------------------------------ Node -----------------------------------
    # ----------------------------------- Paths -----------------------------------
    # Path to directory where to store the data (separate multiple locations by comma).
    "path.data": var.es_cluster_name
    # Path to log files.
    "path.logs": "/es-data/log/"
    # Path to directory containing the configuration file (this file and logging.yml).
    # path.conf: /es-data/configs/
    
  }
}
/*
    ---
    # xpack.security.enabled: "false"
    # cluster.name: "sandbox-es"
    # node.master: "true"
    # node.data: "false"
    # node.ml: "false"
    # node.ingest: "false"
    # node.name: ${HOSTNAME}
    # node.max_local_storage_nodes: 3
    # #processors: ${PROCESSORS}
    # network.host: "_site_"
    # path.data: "/data/data/"
    # path.logs: "/data/log"
    # path.repo: "data/repo"
    # http.cors.enabled: "true"
    # discovery.seed_hosts: ed
    # cluster.initial_master_nodes: es-master-0,es-master-1,es-master-2
    # cluster.routing.allocation.awareness.attributes: zone
    # xpack.license.self_generated.type: "trial"
    # xpack.security.http.ssl.enabled: "false"
    # xpack.monitoring.collection.enabled: "true"
    # xpack.security.transport.ssl.enabled: false

*/



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
    annotations = {
      "kubernetes.io/enforce-mountable-secrets" = true
    }
  }
  secret {
    name = kubernetes_secret.secret.metadata[0].name
  }
}

# Roles define WHAT can be done; role bindings define WHO can do it.
# The distinction between a Role/RoleBinding and a ClusterRole/ClusterRoleBinding is that the Role/
# RoleBinding is a namespaced resource; ClusterRole/ClusterRoleBinding is a cluster-level resource.
# A Role resource defines what actions can be taken on which resources; i.e., which types of HTTP
# requests can be performed on which RESTful resources.
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

resource "kubernetes_stateful_set" "stateful_set" {
  metadata {
    name = var.service_name
    namespace = var.namespace
    # Labels attach to the StatefulSet.
    labels = {
      app = var.app_name
    }
  }
  #
  spec {
    replicas = var.replicas
    service_name = var.service_name_headless
    pod_management_policy = var.pod_management_policy
    revision_history_limit = var.revision_history_limit
    # Pod Selector - You must set the .spec.selector field of a StatefulSet to match the labels of
    # its .spec.template.metadata.labels. Failing to specify a matching Pod Selector will result in
    # a validation error during StatefulSet creation.
    selector {
      match_labels = {
        # It must match the labels in the Pod template (.spec.template.metadata.labels).
        pod_selector_lbl = local.pod_selector_label
      }
    }
    # updateStrategy:
    #   type: RollingUpdate
    #
    # The Pod template.
    template {
      metadata {
        # Labels attach to the Pod.
        labels = {
          app = var.app_name
          # It must match the label for the pod selector (.spec.selector.matchLabels).
          pod_selector_lbl = local.pod_selector_label
          # It must match the label selector of the Service.
          svc_lbl = local.svc_label
          es_lbl = local.es_label
          es_role_lbl = "es-master"
        }
      }
      #
      spec {
        service_account_name = kubernetes_service_account.service_account.metadata[0].name
        affinity {
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              label_selector {
                match_expressions {
                  key = "es_lbl"
                  operator = "In"
                  values = ["${local.es_label}"]
                }
              }
              topology_key = "kubernetes.io/hostname"
            }
          }
        }
        termination_grace_period_seconds = var.termination_grace_period_seconds
        init_container {
          name = "init-commands"
          image = "busybox:1.34.1"
          image_pull_policy = "IfNotPresent"
          command = [
            "/bin/sh",
            "-c",
            "chown -R 1000:1000 /es-data; sysctl -w vm.max_map_count=262144"
          ]
          security_context {
            run_as_non_root = false
            run_as_user = 0
            run_as_group = 0
            read_only_root_filesystem = true
            privileged = true
          }
          volume_mount {
            name = "es-storage"
            mount_path = "/es-data"
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
            run_as_non_root = true
            run_as_user = 1000
            run_as_group = 1000
            read_only_root_filesystem = false
            privileged = false
          }
          # command = [
          #   "/bin/sh",
          #   "-c",
          #   # "./bin/elasticsearch-certutil ca; ./bin/elasticsearch cert --ca es-ca.p12; cp es-ca.p12 /es-data/certs/es-ca.p12"
          #   "./bin/elasticsearch-certutil --silent cert --ca --out /es-data/certs/es-ca.p12 --ca-pass \"\""
          # ]
          # Specifying ports in the pod definition is purely informational. Omitting them has no
          # effect on whether clients can connect to the pod through the port or not. If the
          # container is accepting connections through a port bound to the 0.0.0.0 address, other
          # pods can always connect to it, even if the port isn't listed in the pod spec
          # explicitly. Nonetheless, it is good practice to define the ports explicitly so that
          # everyone using the cluster can quickly see what ports each pod exposes.
          port {
            name = "transport"
            container_port = var.transport_service_target_port  # The port the app is listening.
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
          # A human-readable identifier for a particular instance of Elasticsearch.
          env {
            name = "node.name"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          # By default, Elasticsearch only binds to loopback addresses such as 127.0.0.1 and [::1].
          env {
            name = "network.host"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }
          env {
            name = "ELASTICSEARCH_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.secret.metadata[0].name
                key = "es_username"
              }
            }
          }
          env {
            name = "ELASTICSEARCH_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.secret.metadata[0].name
                key = "es_password"
              }
            }
          }


          env_from {
            config_map_ref {
              # All key-value pairs of the ConfigMap are referenced.
              name = kubernetes_config_map.es_config.metadata[0].name
              # key = "es.conf"
            }
          }


          dynamic "env" {
            for_each = var.env
            content {
              name = env.key
              value = env.value
            }
          }
          # liveness_probe {
          #   tcp_socket {
          #     port = "transport" # var.transport_service_target_port
          #   }
          #   initial_delay_seconds = 20
          #   period_seconds = 10
          # }
          volume_mount {
            name = "es-storage"
            mount_path = "/es-data"
          }


          # volume_mount {
          #   name = "config"
          #   # mount_path = "/es-data/config/elasticsearch.yaml"
          #   mount_path = "/etc/elasticsearch/elasticsearch.yml"
          #   sub_path = "elasticsearch.yml"
          #   read_only = true
          # }


        }



        # volume {
        #   name = "config"
        #   config_map {
        #     name = kubernetes_config_map.es_config.metadata[0].name
        #     # Although ConfigMap should be used for non-sensitive configuration data, make the
        #     # file readable and writable only by the user and group that owns it.
        #     default_mode = "0440"  # Octal
        #     # items {
        #     #   key = "es.env"
        #     #   path = "es.env"  # File name.
        #     # }
        #   }
        # }
          


      }
    }
    # This template will be used to create a PersistentVolumeClaim for each pod.
    # Since PersistentVolumes are cluster-level resources, they do not belong to any namespace, but
    # PersistentVolumeClaims can only be created in a specific namespace; they can only be used by
    # pods in the same namespace.
    volume_claim_template {
      metadata {
        name = "es-storage"
        namespace = var.namespace
        labels = {
          app = var.app_name
        }
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

# Before deploying a StatefulSet, you will need to create a headless Service, which will be used
# to provide the network identity for your stateful pods.
resource "kubernetes_service" "headless_service" {  # For inter-node communication.
  metadata {
    name = var.service_name_headless
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  spec {
    selector = {
      # All pods with the svc_lbl=local.svc_label label belong to this service.
      svc_lbl = local.svc_label
    }
    session_affinity = var.service_session_affinity
    port {
      name = "transport"  # Inter-node communication.
      port = var.transport_service_port
      target_port = var.transport_service_target_port
      protocol = "TCP"
    }
    type = var.service_type
    cluster_ip = "None"  # Headless Service.
    publish_not_ready_addresses = var.publish_not_ready_addresses
  }
}
