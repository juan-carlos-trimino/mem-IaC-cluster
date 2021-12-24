# The application and its microservices

This application is based on xxxxxxxx. It is composed of sssss microservices; vis., `a`, `b`, `c`, and `d`.
The app contains a single RabbitMQ server instance; the RabbitMQ server contains multiple queues
  with different names.
Each microservice has its own private database; the databases are hosted on a shared server.

***
<br>

# Gateway/Reverse Proxy (mem-gateway)

The gateway is the entry point to the app; it provides a REST API so the front end can interact with the backend.

```
/***
Import the microservice Terraform module to deploy the mem-gateway.
***/
module "mem-gateway" {
  # Specify the location of the module, which contains the file main.tf.
  source = "./modules/pri-microservice"
  # Set input variables to configure the microservice module for the mem-gateway.
  dir_name = "../../mem-gateway/gateway"
  app_name = var.app_name
  app_version = var.app_version
  namespace = local.namespace
  replicas = 3
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
    initial_delay_seconds = 120
    period_seconds = 20
    timeout_seconds = 2
    failure_threshold = 10
    success_threshold = 1
  }]
  service_name = "mem-gateway"
  service_type = "LoadBalancer"
  service_session_affinity = "ClientIP"
}
```
***
<br>

# History (mem-history)

It records the user's viewing history.

video-streaming -> RabbitMQ('viewed' message) -> history -> mongoDB('history' db)


(1) 'viewed' message is how the video-streaming microservice informs the history microservice
     that the user has watched a video.
(2) The history microservice receives messages from the video-streaming microservice, and it
    records them in its own database.

```
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
    initial_delay_seconds = 100
    period_seconds = 15
    timeout_seconds = 2
    failure_threshold = 3
    success_threshold = 1
  }]
  service_name = "mem-history"
}
```
***
<br>

# Metadata (mem-metadata)

It records details and metadata about each video.

* The app contains a single RabbitMQ server instance; the RabbitMQ server contains multiple queues
  with different names.
* Each microservice has its own private database; the databases are hosted on a shared server.

```
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
```
***
<br>

# MongoDB (mem-mongodb)

```
module "mem-mongodb" {
  source = "./modules/pub-microservice"
  app_name = var.app_name
  app_version = var.app_version
  image_tag = "mongo:4.2.8"
  # image_tag = "rhscl/mongodb-36-rhel7"
  namespace = local.namespace
  /*
  Limits and request for CPU resources are measured in millicores. If the container needs one full
  core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the value of
  '250m.'
  */
  qos_limits_cpu = "400m"
  #qos_limits_memory = "1Gi"
  qos_limits_memory = "500Mi"
  pvc_name = "mongodb-pvc"
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "5Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  #pvc_storage_class_name = "ibmc-s3fs-standard-regional"
  #bucket_name = var.bucket_name
  #private_endpoint = var.private_endpoint
  #api_key = var.api_key
  #service_instance_id = var.service_instance_id
  service_name = "mem-mongodb"
  service_port = 27017
  service_target_port = 27017
  # env = {
  #   #MONGO_INITDB_ROOT_USERNAME = "root"
  #   #MONGO_INITDB_ROOT_PASSWORD = "example"
  #   MONGODB_ADMIN_PASSWORD = "jct123"
  #   MONGODB_USER = "guest"
  #   MONGODB_PASSWORD = "guest"
  #   #MONGODB_DATABASE = "history"
  #   MONGODB_DATABASE = "metadata"
  # }
}
```
***
<br>

# RabbitMQ (mem-rabbitmq)

```
module "mem-rabbitmq" {
  # Specify the location of the module, which contains the file main.tf.
  source = "./modules/pri-microservice"
  # Set input variables to configure the microservice module for the ms-rabbitmq.
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
```
***
<br>

# Video-Storage (mem-video-storage)

An abstraction of the file storage provider. One advantage of this architecture (separation of concerns and single responsibility principle) is that the video storage microservice can be easily swapped out and be replaced with an alternative.

#### `Note`
IBM's Cloud Object Storage (COS) is `S3 (Simple Storage Service)` compatible and can, thus, be used with any S3-compatible tooling. The fundamental unit of object storage is called a `bucket`.

```
module "mem-video-storage" {
  source = "./modules/pri-microservice"
  dir_name = "../../mem-video-storage/video-storage"
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
    #
    AUTHENTICATION_TYPE: "iam"
    API_KEY: var.api_key
    SERVICE_INSTANCE_ID: var.resource_instance_id
    ENDPOINT: var.public_endpoint
    #
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
```
***
<br>

# Video-Streaming (mem-video-streaming)

It streams videos from storage to be watched by the user.

external cloud storage -> video-storage -> video-streaming -> gateway -> user UI
                                                |
                         												-> RabbitMQ (viewed message) -> history

```
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
```
***
<br>

# Video-Upload (mem-video-upload)

It orchestrates upload of videos to storage.


user UI -> gateway -> video-upload -> video-storage -> external cloud storage
                           |
                           -> RabbitMQ (uploaded message) -> metadata

```
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
```
***
<br>



RESOURCEGROUP=Default
COS_NAME_RANDOM=$(date | md5sum | head -c10)
COS_NAME=$COS_NAME_RANDOM-cos-1
COS_CREDENTIALS=$COS_NAME-credentials
COS_PLAN=Lite
COS_BUCKET_NAME=$(date | md5sum | head -c10)-bucket-1
REGION=us-south
COS_PRIVATE_ENDPOINT=s3.private.$REGION.cloud-object-storage.appdomain.cloud



emptyDir
An emptyDir volume is first created when a Pod is assigned to a node, and exists as long as that Pod is running on that node. As the name says, the emptyDir volume is initially empty. All containers in the Pod can read and write the same files in the emptyDir volume, though that volume can be mounted at the same or different paths in each container. When a Pod is removed from a node for any reason, the data in the emptyDir is deleted permanently.
Note: A container crashing does not remove a Pod from a node. The data in an emptyDir volume is safe across container crashes.



Data is available to all nodes within the availability zone where the file storage exists, but the accessMode parameter on the PersistentVolumeClaim determines if multiple pods are able to mount a volume specificed by a PVC. The possible values for this parameter are:

ReadWriteMany: The PVC can be mounted by multiple pods. All pods can read from and write to the volume.
ReadOnlyMany: The PVC can be mounted by multiple pods. All pods have read-only access.
ReadWriteOnce: The PVC can be mounted by one pod only. This pod can read from and write to the volume.

