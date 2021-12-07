/***
How to use the module to deploy the microservices.
***/
locals {
  namespace = kubernetes_namespace.ns.metadata[0].name
  cr_login_server = "docker.io"
  db_metadata = "metadata"
  db_history = "history"
  # DNS translates hostnames to IP addresses; the container name is the hostname. When using Docker
  # and Docker Compose, DNS works automatically.
  # In K8s, a service makes the deployment accessible by other containers via DNS.
  svc_dns_video_storage = "mem-video-storage.${local.namespace}.svc.cluster.local"
  svc_dns_metadata = "mem-metadata.${local.namespace}.svc.cluster.local"
  svc_dns_gateway = "mem-gateway.${local.namespace}.svc.cluster.local"
  svc_dns_history = "mem-history.${local.namespace}.svc.cluster.local"
  svc_dns_video_upload = "mem-video-upload.${local.namespace}.svc.cluster.local"
  svc_dns_video_streaming = "mem-video-streaming.${local.namespace}.svc.cluster.local"
  # By default, the guest user is prohibited from connecting from remote hosts; it can only connect
  # over a loopback interface (i.e. localhost). This applies to connections regardless of the
  # protocol. Any other users will not (by default) be restricted in this way.
  # It is possible to allow the guest user to connect from a remote host by setting the
  # loopback_users configuration to none.
  # See rabbitmq.conf
  svc_dns_rabbitmq = "amqp://guest:guest@mem-rabbitmq.${local.namespace}.svc.cluster.local:5672"
  svc_dns_db = "mongodb://mem-mongodb.${local.namespace}.svc.cluster.local:27017"
  #svc_dns_db = "mongodb://guest:guest@mem-mongodb.${local.namespace}.svc.cluster.local:27017/metadata?authSource=metadata&w=1"
  #svc_dns_db1 = "mongodb://guest:guest@mem-mongodb.${local.namespace}.svc.cluster.local:27017/history?authSource=history&w=1"
}

/***
Import the microservice Terraform module to deploy the ms-gateway.
***/
module "ms-gateway" {
  # Specify the location of the module, which contains the file main.tf.
  source = "./modules/pri-microservice"
  # Set input variables to configure the microservice module for the ms-gateway.
  dir_name = "gateway"
  app_name = var.app_name
  app_version = var.app_version
  namespace = local.namespace
  replicas = 3
  qos_limits_cpu = "400m"
  qos_limits_memory = "400Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  # Configure environment variables specific to the ms-gateway.
  env = {
    SVC_DNS_METADATA: local.svc_dns_metadata
    SVC_DNS_HISTORY: local.svc_dns_history
    SVC_DNS_VIDEO_UPLOAD: local.svc_dns_video_upload
    SVC_DNS_VIDEO_STREAMING: local.svc_dns_video_streaming
    MAX_RETRIES: 20
  }
  readiness_probe = [{
    http_get = [{
      #host = local.svc_dns_gateway
      path = "/readiness"
      port = 0
      scheme = "HTTP"
    }]
    initial_delay_seconds = 210
    period_seconds = 20
    timeout_seconds = 2
    failure_threshold = 10
    success_threshold = 1
  }]
  service_name = "mem-gateway"
  service_type = "LoadBalancer"
  service_session_affinity = "ClientIP"
}

module "ms-rabbitmq" {
  # Specify the location of the module, which contains the file main.tf.
  source = "./modules/pri-microservice"
  # Set input variables to configure the microservice module for the ms-rabbitmq.
  dir_name = "rabbitmq"
  app_name = var.app_name
  app_version = var.app_version
  # This image has the RabbitMQ dashboard.
  # image_tag = "rabbitmq:3.9.7-management-alpine"
  # image_tag = "rabbitmq:3.9.7-alpine"
  namespace = local.namespace
  qos_limits_cpu = "400m"
  qos_limits_memory = "300Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  service_name = "mem-rabbitmq"
  service_port = 5672
  service_target_port = 5672
}

/***
Record details and metadata about each video.
***/
module "ms-metadata" {
  source = "./modules/pri-microservice"
  dir_name = "metadata"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 3
  namespace = local.namespace
  qos_requests_memory = "50Mi"
  qos_limits_memory = "100Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  env = {
    SVC_DNS_RABBITMQ: local.svc_dns_rabbitmq
    SVC_DNS_DB: local.svc_dns_db
    DB_NAME: local.db_metadata
    MAX_RETRIES: 20
  }
  readiness_probe = [{
    http_get = [{
      #host = local.svc_dns_metadata
      path = "/readiness"
      port = 0
      scheme = "HTTP"
    }]
    initial_delay_seconds = 180
    period_seconds = 15
    timeout_seconds = 2
    failure_threshold = 3
    success_threshold = 1
  }]
  service_name = "mem-metadata"
}

/***
Orchestrate upload of videos to storage.
***/
module "ms-video-upload" {
  source = "./modules/pri-microservice"
  dir_name = "video-upload"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 3
  namespace = local.namespace
  qos_requests_memory = "150Mi"
  qos_limits_memory = "300Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  env = {
    SVC_DNS_RABBITMQ: local.svc_dns_rabbitmq
    SVC_DNS_VIDEO_STORAGE: local.svc_dns_video_storage
    MAX_RETRIES: 20
  }
  readiness_probe = [{
    http_get = [{
      host = local.svc_dns_video_upload
      path = "/readiness"
      port = 0
      scheme = "HTTP"
    }]
    initial_delay_seconds = 180
    period_seconds = 15
    timeout_seconds = 2
    failure_threshold = 3
    success_threshold = 1
  }]
  service_name = "mem-video-upload"
}

/***
Stream videos from storage to be watched by the user.
***/
module "ms-video-streaming" {
  source = "./modules/pri-microservice"
  dir_name = "video-streaming"
  app_name = var.app_name
  app_version = var.app_version
  namespace = local.namespace
  replicas = 3
  qos_requests_memory = "150Mi"
  qos_limits_memory = "300Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  env = {
    SVC_DNS_RABBITMQ: local.svc_dns_rabbitmq
    SVC_DNS_VIDEO_STORAGE: local.svc_dns_video_storage
    MAX_RETRIES: 20
  }
  readiness_probe = [{
    http_get = [{
      host = local.svc_dns_video_streaming
      path = "/readiness"
      port = 0
      scheme = "HTTP"
    }]
    initial_delay_seconds = 180
    period_seconds = 15
    timeout_seconds = 2
    failure_threshold = 3
    success_threshold = 1
  }]
  service_name = "mem-video-streaming"
}

/***
Responsible for storing and retrieving videos from external cloud storage.
***/
module "ms-video-storage" {
  source = "./modules/pri-microservice"
  dir_name = "video-storage"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 3
  namespace = local.namespace
  dns_name = "mem-video-storage"
  qos_limits_cpu = "300m"
  qos_limits_memory = "500Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  env = {
    BUCKET_NAME: var.bucket_name
    API_KEY: var.api_key
    ENDPOINT: var.public_endpoint
    SERVICE_INSTANCE_ID: var.service_instance_id
    SIGNATURE_VERSION: var.signature_version
    MAX_RETRIES: 20
  }
  service_name = "mem-video-storage"
}

/***
Record the user's viewing history.
***/
module "ms-history" {
  source = "./modules/pri-microservice"
  dir_name = "history"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 3
  namespace = local.namespace
  qos_requests_memory = "50Mi"
  qos_limits_memory = "100Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  env = {
    SVC_DNS_RABBITMQ: local.svc_dns_rabbitmq
    SVC_DNS_DB: local.svc_dns_db
    DB_NAME: local.db_history
    MAX_RETRIES: 20
  }
  readiness_probe = [{
    http_get = [{
      #host = local.svc_dns_history
      path = "/readiness"
      port = 0
      scheme = "HTTP"
    }]
    initial_delay_seconds = 180
    period_seconds = 15
    timeout_seconds = 2
    failure_threshold = 3
    success_threshold = 1
  }]
  service_name = "mem-history"
}
