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
}

module "mem-gateway" {
  # Specify the location of the module, which contains the file main.tf.
  source = "./modules/pri-microservice"
  dir_name = "../../mem-gateway/gateway"
  app_name = var.app_name
  app_version = var.app_version
  namespace = local.namespace
  replicas = 1
  qos_limits_cpu = "400m"
  qos_limits_memory = "400Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  # Configure environment variables specific to the mem-gateway.
  env = {
    SVC_DNS_METADATA: local.svc_dns_metadata
    SVC_DNS_HISTORY: local.svc_dns_history
    SVC_DNS_VIDEO_UPLOAD: local.svc_dns_video_upload
    SVC_DNS_VIDEO_STREAMING: local.svc_dns_video_streaming
    MAX_RETRIES: 20
  }
  readiness_probe = [{
    http_get = [{
      path = "/readiness"
      port = 0
      scheme = "HTTP"
    }]
    initial_delay_seconds = 30
    period_seconds = 20
    timeout_seconds = 2
    failure_threshold = 4
    success_threshold = 1
  }]
  service_name = "mem-gateway"
  service_type = "LoadBalancer"
  service_session_affinity = "ClientIP"
}

module "mem-history" {
  source = "./modules/pri-microservice"
  dir_name = "../../mem-history/history"
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
      path = "/readiness"
      port = 0
      scheme = "HTTP"
    }]
    initial_delay_seconds = 30
    period_seconds = 20
    timeout_seconds = 2
    failure_threshold = 4
    success_threshold = 1
  }]
  service_name = "mem-history"
}

module "mem-metadata" {
  source = "./modules/pri-microservice"
  dir_name = "../../mem-metadata/metadata"
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
      path = "/readiness"
      port = 0
      scheme = "HTTP"
    }]
    initial_delay_seconds = 100
    period_seconds = 15
    timeout_seconds = 2
    failure_threshold = 3
    success_threshold = 1
  }]
  service_name = "mem-metadata"
}

module "mem-rabbitmq" {
  # Specify the location of the module, which contains the file main.tf.
  source = "./modules/pri-microservice"
  dir_name = "../../mem-rabbitmq/rabbitmq"
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

module "mem-video-storage" {
  source = "./modules/pri-microservice"
  dir_name = "../../mem-video-storage/video-storage"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 3
  namespace = local.namespace
  qos_limits_cpu = "300m"
  qos_limits_memory = "500Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  env = {
    BUCKET_NAME: var.bucket_name
    # Without HMAC.
    AUTHENTICATION_TYPE: "iam"
    API_KEY: var.api_key
    SERVICE_INSTANCE_ID: var.resource_instance_id
    ENDPOINT: var.public_endpoint
    # With HMAC.
    # AUTHENTICATION_TYPE: "hmac"
    # REGION: var.region1
    # ACCESS_KEY_ID: var.access_key_id
    # SECRET_ACCESS_KEY: var.secret_access_key
    # ENDPOINT: var.public_endpoint
    #
    MAX_RETRIES: 20
  }
  service_name = "mem-video-storage"
}

module "mem-video-streaming" {
  source = "./modules/pri-microservice"
  dir_name = "../../mem-video-streaming/video-streaming"
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
    initial_delay_seconds = 100
    period_seconds = 15
    timeout_seconds = 2
    failure_threshold = 3
    success_threshold = 1
  }]
  service_name = "mem-video-streaming"
}

module "mem-video-upload" {
  source = "./modules/pri-microservice"
  dir_name = "../../mem-video-upload/video-upload"
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
    initial_delay_seconds = 100
    period_seconds = 15
    timeout_seconds = 2
    failure_threshold = 3
    success_threshold = 1
  }]
  service_name = "mem-video-upload"
}
