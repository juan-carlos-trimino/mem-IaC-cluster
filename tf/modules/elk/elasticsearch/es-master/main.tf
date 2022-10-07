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
  default = "20Gi"
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
########################################## Session affinity and Web Browsers (for LoadBalancer Services)
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
# resource "kubernetes_cluster_role_binding" "cluster_role_binding" {
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

# There are important reasons for using a StatefulSet instead of a Deployment: sticky identity,
# simple network identifiers, stable persistent storage and the ability to perform ordered rolling
# upgrades.
#
# $ kubectl get sts -n memories
#
#
# It is interesting to follow the logs of any of the master-node pods to witness the master election among them
# and then later on when new data and client nodes are added.
# root$ kubectl -n memories logs -f pod/mem-elasticsearch-master-0 | grep ClusterApplierService
# https://jsonformatter.curiousconcept.com/#
# It can be seen that es-master pod named es-master-594b58b86c-bj7g7 was elected as the master and other 2 pods added to it and each other.

# Windows CMD
# C:\> kubectl -n memories logs -f pod/mem-elasticsearch-master-0 | findstr "ClusterApplierService"
# Windows PowerShell
# PS C:\> kubectl -n memories logs -f pod/mem-elasticsearch-master-0 | Select-String "ClusterApplierService"
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
    # Headless service that gives network identity to the Elasticsearch nodes and enables them to
    # cluster. The name of the service that governs this StatefulSet. This service must exist
    # before the StatefulSet and is responsible for the network identity of the set. Pods get
    # DNS/hostnames that follow the pattern: pod-name.service-name.namespace.svc.cluster.local.
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
          # It must match the label for the pod selector (.spec.selector.matchLabels).
          pod_selector_lbl = local.pod_selector_label
          svc_lbl = local.svc_label
        }
      }
      #
      spec {
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
        termination_grace_period_seconds = var.termination_grace_period_seconds
        # Elasticsearch requires vm.max_map_count to be at least 262144. If the OS already sets up
        # this number to a higher value, feel free to remove the init container.
        # Increase the default vm.max_map_count to 262144
        # https://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html#docker-cli-run-prod-mode
        init_container {
          name = "init-sysctl"
          image = "busybox:1.34.1"
          image_pull_policy = "IfNotPresent"
          command = ["sysctl", "-w", "vm.max_map_count=262144"]
          security_context {
            run_as_non_root = false
            run_as_user = 0
            run_as_group = 0
            read_only_root_filesystem = true
            privileged = true
          }
        }
        # Fix the permissions on the volume.
        init_container {
          name = "fix-permissions"
          image = "busybox:1.34.1"
          image_pull_policy = "IfNotPresent"
          command = ["/bin/sh", "-c", "chown -R 1000:1000 /es-data"]
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
            run_as_group = 1000
            run_as_user = 1000
            read_only_root_filesystem = false
            privileged = false
          }
          ###################################################
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
          dynamic "env" {
            for_each = var.env
            content {
              name = env.key
              value = env.value
            }
          }
          # liveness_probe {
          #   exec {
          #     command = ["rabbitmq-diagnostics", "status", "--erlang-cookie", "$(RABBITMQ_ERLANG_COOKIE)"]
          #   }
          #   initial_delay_seconds = 60
          #   # See https://www.rabbitmq.com/monitoring.html for monitoring frequency recommendations.
          #   period_seconds = 60
          #   timeout_seconds = 15
          #   failure_threshold = 3
          #   success_threshold = 1
          # }
          # readiness_probe {
          #   exec {
          #     command = ["rabbitmq-diagnostics", "status", "--erlang-cookie", "$(RABBITMQ_ERLANG_COOKIE)"]
          #   }
          #   initial_delay_seconds = 20
          #   period_seconds = 60
          #   timeout_seconds = 10
          # }
          volume_mount {
            name = "es-storage"
            mount_path = "/es-data"
          }
        }
      }
    }
    # This template will be used to create a PersistentVolumeClaim for each pod.
    # Since PersistentVolumes are cluster-level resources, they do not belong to any namespace, but
    # PersistentVolumeClaims can only be created in a specific namespace; they can only be used by
    # pods in the same namespace.
    #
    # In order for RabbitMQ nodes to retain data between Pod restarts, node's data directory must
    # use durable storage. A Persistent Volume must be attached to each RabbitMQ Pod.
    #
    # If a transient volume is used to back a RabbitMQ node, the node will lose its identity and
    # all of its local data in case of a restart. This includes both schema and durable queue data.
    # Syncing all of this data on every node restart would be highly inefficient. In case of a loss
    # of quorum during a rolling restart, this will also lead to data loss.
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
#
# Unlike stateless pods, stateful pods sometimes need to be addressable by their hostname. For this
# reason, a StatefulSet requires a corresponding governing headless Service that's used to provide
# the actual network identity to each pod. Through this Service, each pod gets its own DNS entry
# thereby allowing its peers in the cluster to address the pod by its hostname. For example, if the
# governing Service belongs to the default namespace and is called service1, and the pod name is
# pod-0, the pod can be reached by its fully qualified domain name of
# pod-0.service1.default.svc.cluster.local.
#
# To list the SRV records for the stateful pods, perform a DNS lookup from inside a pod running in
# the cluster:
# $ kubectl run -it srvlookup --image=tutum/dnsutils --rm --restart=Never -- dig SRV <service-name>.<namespace>.svc.cluster.local
#
# $ kubectl run -it srvlookup --image=tutum/dnsutils --rm --restart=Never -- dig SRV mem-elasticsearch-headless.memories.svc.cluster.local
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
