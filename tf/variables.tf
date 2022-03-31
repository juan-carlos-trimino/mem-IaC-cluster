####################
# GLOBAL VARIABLES #
####################
variable app_name {
  type = string
  description = "The name of the application."
  default = "memories"
}

variable app_version {
  type = string
  description = "The application version."
  default = "1.0.0"
}

##########
# Locals #
##########
locals {
  namespace = kubernetes_namespace.ns.metadata[0].name
  # DNS translates hostnames to IP addresses; the container name is the hostname. When using Docker
  # and Docker Compose, DNS works automatically.
  # In K8s, a service makes the deployment accessible by other containers via DNS.
  svc_dns_gateway = "mem-gateway.${local.namespace}.svc.cluster.local"
  svc_dns_metadata = "mem-metadata.${local.namespace}.svc.cluster.local"
  svc_dns_history = "mem-history.${local.namespace}.svc.cluster.local"
  svc_dns_video_storage = "mem-video-storage.${local.namespace}.svc.cluster.local"
  svc_dns_video_upload = "mem-video-upload.${local.namespace}.svc.cluster.local"
  svc_dns_video_streaming = "mem-video-streaming.${local.namespace}.svc.cluster.local"
  svc_dns_elasticsearch = "mem-elasticsearch.${local.namespace}.svc.cluster.local:9200"
  svc_dns_kibana = "mem-kibana.${local.namespace}.svc.cluster.local:5601"
  # By default, the guest user is prohibited from connecting from remote hosts; it can only connect
  # over a loopback interface (i.e. localhost). This applies to connections regardless of the
  # protocol. Any other users will not (by default) be restricted in this way.
  # It is possible to allow the guest user to connect from a remote host by setting the
  # loopback_users configuration to none.
  # See rabbitmq.conf
  svc_dns_rabbitmq = "amqp://${var.rabbitmq_default_user}:${var.rabbitmq_default_pass}@mem-rabbitmq.${local.namespace}.svc.cluster.local:5672"
  svc_dns_db = "mongodb://mem-mongodb.${local.namespace}.svc.cluster.local:27017"
  # svc_dns_db = "mongodb://${var.mongodb_username}:${var.mongodb_password}@mem-mongodb.${local.namespace}.svc.cluster.local:27017"
  # Stateful stuff
  # svc_dns_db = "mongodb://mem-mongodb-0.mem-mongodb.${local.namespace}.svc.cluster.local,mem-mongodb-1.mem-mongodb.${local.namespace}.svc.cluster.local,mem-mongodb-2.mem-mongodb.${local.namespace}.svc.cluster.local:27017"
}
