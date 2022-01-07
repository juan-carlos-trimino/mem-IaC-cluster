# The application (memories)
### Acknowledgment
This project would not have been possible without the book `Bootstrapping Microservices with Docker, Kubernetes and Terraform` by `Ashley Davis`. The book was my motivation to learn `node.js`, but, more importantly, the book was my introduction to `Terraform`. `Terraform` makes building the cloud infrastructure (the Kubernetes cluster and storage requirements) and deploying the application simpler. Needless to say, I highly recommend the book.

<br>

This is a video-streaming `distributed application` composed of the following **eight** microservices: *gateway/reverse proxy*, *history*, *metadata*, *video storage*, *video streaming*, *video upload*, *MongoDB*, and *RabbitMQ*; MongoDB and RabbitMQ are third-party servers. The application was developed and tested using `Node.js`, `Terraform`, `Red Hat OpenShift (Kubernetes)`, `IBM Cloud Storage Object (COS)`, `Docker`, `Docker Hub (container registry)`, `MongoDB`, and `RabbitMQ`. The name of the application is **memories**.

***
<br>

# Repos

```
memories-meta-repo
 ├ .gitignore
 └ .meta
```

```
IaC-cluster
 ├ tf
 | ├ cluster_config
 | | └ .gitkeep
 | ├ modules
 | | ├ pri-microservice
 | | | └ main.tf
 | | ├ pub-microservice
 | | | └ main.tf
 | | └ .gitkeep
 | ├ data.tf
 | ├ pri-microservices.tf
 | ├ providers.tf
 | ├ pub-microservices.tf
 | ├ resource-group.tf
 | ├ variables.tf
 | └ variables_no_push.tf.template
 ├ .gitignore
 ├ LICENSE
 └ README.md
```

```
IaC-storage
 ├ tf
 | ├ ibm-cos
 | | ├ create-bucket
 | | | ├ data.tf
 | | | ├ input.tfvars
 | | | ├ main.tf
 | | | ├ resource-group.tf
 | | | ├ variables.tf
 | | | ├ variables.tfvars
 | | | ├ variables_no_push.tf.template
 | | | └ versions.tf
 | | ├ create-instance
 | | | ├ data.tf
 | | | ├ input.tfvars
 | | | ├ main.tf
 | | | ├ resource-group.tf
 | | | ├ variables.tf
 | | | ├ variables.tfvars
 | | | ├ variables_no_push.tf.template
 | | | └ versions.tf
 | | └ modules
 | | | ├ bucket
 | | | | ├ main.tf
 | | | | ├ variables.tf
 | | | | ├ variables_no_push.tf.template
 | | | | └ versions.tf
 | | | ├ instance
 | | | | ├ main.tf
 | | | | ├ variables.tf
 | | | | ├ variables_no_push.tf.template
 | | | | └ versions.tf
 | | | └ .gitkeep
 | └ .gitkeep
 ├ .gitignore
 ├ LICENSE
 └ README.md
```

```
mem-gateway
 ├ gateway
 | ├ public
 | | ├ css
 | | | ├ app.css
 | | | └ tailwind.min.css
 | | ├ js
 | | | └ upload.js
 | ├ src
 | | ├ views
 | | | ├ history.hbs
 | | | ├ play-video.hbs
 | | | ├ upload-video.hbs
 | | | └ video-list.hbs
 | | └ index.js
 | ├ .dockerignore
 | ├ Dockerfile-dev
 | ├ Dockerfile-prod
 | ├ package-lock.json
 | └ package.json
 ├ .gitignore
 ├ LICENSE
 └ README.md
```

```
mem-history
 ├ history
 | ├ src
 | | └ index.js
 | ├ .dockerignore
 | ├ Dockerfile-dev
 | ├ Dockerfile-prod
 | ├ package-lock.json
 | └ package.json
 ├ .gitignore
 ├ LICENSE
 └ README.md
```

```
mem-metadata
 ├ metadata
 | ├ src
 | | └ index.js
 | ├ .dockerignore
 | ├ Dockerfile-dev
 | ├ Dockerfile-prod
 | ├ package-lock.json
 | └ package.json
 ├ .gitignore
 ├ LICENSE
 └ README.md
```

```
mem-rabbitmq
 ├ rabbitmq
 | ├ .dockerignore
 | ├ Dockerfile-prod
 | └ rabbitmq.conf
 ├ .gitignore
 ├ LICENSE
 └ README.md
```

```
mem-video-storage
 ├ video-storage
 | ├ src
 | | └ index.js
 | ├ .dockerignore
 | ├ Dockerfile-dev
 | ├ Dockerfile-prod
 | ├ package-lock.json
 | └ package.json
 ├ .gitignore
 ├ LICENSE
 └ README.md
```

```
mem-video-streaming
 ├ video-streaming
 | ├ src
 | | └ index.js
 | ├ .dockerignore
 | ├ Dockerfile-dev
 | ├ Dockerfile-prod
 | ├ package-lock.json
 | └ package.json
 ├ .gitignore
 ├ LICENSE
 └ README.md
```

```
mem-video-upload
 ├ video-upload
 | ├ src
 | | └ index.js
 | ├ .dockerignore
 | ├ Dockerfile-dev
 | ├ Dockerfile-prod
 | ├ package-lock.json
 | └ package.json
 ├ .gitignore
 ├ LICENSE
 └ README.md
```
***
<br>

# Meta Repo (memories-meta-repo)

A `meta repo` tracks multiple repositories as a single aggregate repository thereby making the management of multiple repositories easier. The `meta` tool is available here:

* https://github.com/mateodelnorte/meta

To install `meta`:
```
>$ npm i -g meta
```

To create a `meta-repo` project:
```
>$ mkdir memories-meta-repo && cd memories-meta-repo
>$ git init
```

To initialize the new repository as a `meta repo`:<br>
(`meta` will create a `.meta` file that contains a collection of separate repositories.)
```
>$ meta init
```

`meta` performs `Git` commands against the entire collection of repositories.<br>
Listed below are some useful `meta` commands

```
To clone the meta repo and all of its children repositories:
>$ meta git clone https://github.com/juan-carlos-trimino/memories-meta-repo.git

To get meta project updates, first get the .meta file and then get the missing projects:
>$ git pull origin master
>$ meta git update

To list all of the files in each project:
>$ meta exec "ls -al"

To pull code changes for all repositories:
>$ meta git pull

>$ meta git status
```
***
<br>

# Gateway/Reverse Proxy (mem-gateway)

In a typical microservices deployment, microservices are not exposed directly to client applications; i.e., microservices are behind a set of APIs that is exposed to the outside world via a gateway. **The gateway is the entry point to the microservices deployment**, which screens all incoming messages for security and other quality of service (QoS) features. Since the gateway deals with north/south traffic, it is mostly about **edge security**. To reiterate, the gateway is **the only entry point to the microservices deployment for requests originating from *outside***.

The current implementation of the gateway **does not provide any *edge security* at all**, but it is **the only entry point to the microservices deployment for requests originating from *outside***. There are many options for reverse proxies available such as `Nginx`, `Zuul`, `HAProxy`, and `Traefik`.

## Code
**`mem-gateway` microservice (index.js).**
- It is the single-entry point to the application.
- It provides the front-end UI that allows the users to interact with the application.
- It provides a REST API for the front-end to interact with the backend.
- The *UI* is implemented as a traditional *server-rendered* web page instead of a *single-page (SPA)* rendered in the browser.
- Requests:
  - The list of uploaded videos: `user -> gateway -> metadata`<br>
    The main page shows the list of uploaded videos. The route handler starts by requesting data from the metadata microservice. It then renders the web page using the video-list template and input the list of videos as the template's data.
  - The user's viewing history: `user -> gateway -> history`
  - Stream a video: `user -> gateway -> video-streaming`<br>
    The streaming video is piped through the video-storage, through the video-streaming, through the gateway, and finally, displayed to the user through the video element in its web browser.
  - Upload a video: `user -> gateway -> video-upload`

**`mem-gateway` module (pri-microservices.tf).**
```
module "mem-gateway" {
  source = "./modules/pri-microservice"
  dir_name = "../../mem-gateway/gateway"
```
**source** -> Specify the location of the module, which contains the file main.tf.<br>
**dir_name** -> Specify the path use in the building of the Docker image.

```
  app_name = var.app_name
  app_version = var.app_version
  namespace = local.namespace
```
**app_name** -> Application name.<br>
**app_version** -> Application version.<br>
**namespace** -> The namespace.

```
  replicas = 2
  qos_limits_cpu = "400m"
  qos_limits_memory = "400Mi"
```
**replicas** -> Redundancy is implemented by replication; replication is also used for increased performance.<br>
**qos_limits_cpu/qos_limits_memory** -> QoS class: Guaranteed.

```
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
```
**cr_login_server** -> The URL of the container registry.<br>
**cr_username** -> The username for Docker Hub.<br>
**cr_password** -> The password for Docker Hub.

```
  env = {
    SVC_DNS_METADATA: local.svc_dns_metadata
    SVC_DNS_HISTORY: local.svc_dns_history
    SVC_DNS_VIDEO_UPLOAD: local.svc_dns_video_upload
    SVC_DNS_VIDEO_STREAMING: local.svc_dns_video_streaming
    MAX_RETRIES: 20
  }
```
**env** -> The environment variables for mem-gateway.<br>
**SVC_DNS_\*** -> DNS records for services.<br>
**MAX_RETRIES** -> When a microservice connects to an upstream dependency, it must wait for the dependency (e.g., RabbitMQ, MongoDB, or another microservice) to boot up before it can connect and make use of the dependency. If the microservice tries to connect too early, the default behavior is to throw an unhandled exception that most likely aborts the microservice; the microservice will constantly crash and restart while the dependency is down. To avoid wasting resources by constantly restarting the microservice, it is best to let the microservice wait quietly until its dependency becomes available; i.e., the microservice will attempt to connect after a given amount of time has elapsed. This can potentially happen when the application is first booting up, the dependency crashes and Kubernetes automatically restarts it, or the dependency is taken down temporarily for maintenance. This sets the maximum number of attempts to connect.

```
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
  ```
**readiness_probe** -> It determines if the microservice has started and is ready to start accepting requests.<br>
**http_get.path** -> Path to access on the HTTP server. Defaults to /.<br>
**http_get.port** -> Name or number of the port to access on the container. Number must be in the range 1 to 65535. To use a *random free port*, set the port to zero (0).<br>
**http_get.scheme** -> Scheme to use for connecting to the host (HTTP or HTTPS). Defaults to HTTP.<br>
**initial_delay_seconds** -> Number of seconds after the container has started before liveness or readiness probes are initiated. Defaults to 0 seconds. Minimum value is 0.<br>
**period_seconds** -> How often (in seconds) to perform the probe. Default to 10 seconds. Minimum value is 1.<br>
**timeout_seconds** -> Number of seconds after which the probe times out. Defaults to 1 second. Minimum value is 1.<br>
**failure_threshold** -> When a probe fails, Kubernetes will try *failureThreshold* times before giving up. Giving up in case of *liveness probe* means restarting the container. In case of *readiness probe*, the Pod will be marked *Unready*. Defaults to 3. Minimum value is 1.<br>
**success_threshold** -> Minimum consecutive successes for the probe to be considered successful after having failed. Defaults to 1. Must be 1 for liveness and startup Probes. Minimum value is 1.

  ```
  service_name = "mem-gateway"
  service_type = "LoadBalancer"
  service_session_affinity = "ClientIP"
}
```
**service_name** -> The name of the service.<br>
**service_type** -> The `ServiceType` specifies what kind of `Service` to use. The `LoadBalancer` exposes the `Service` **externally** using a cloud provider's load balancer. The `ClusterIP` (default) exposes the `Service` on a **cluster-internal** IP; i.e, the `Service` is only reachable from within the cluster.<br>
**service_session_affinity** -> To have all requests made by a certain client to be redirected to the same pod every time, set the service's `sessionAffinity` property to `ClientIP` instead of `None` (default).
***
<br>

# History (mem-history)

It records the user's viewing history.

## Code
**`mem-history` microservice (index.js).**
- It uses the `MongoDB` server to store the viewing history in the `histroy` database.
- It subscribes to the `viewed queue` of `RabbitMQ` to receive `viewed messages`.
- The *history* microservice receives messages from the *video-streaming* microservice, and it records them in its database.

**`mem-history` module (pri-microservices.tf).**
```
module "mem-history" {
  source = "./modules/pri-microservice"
  dir_name = "../../mem-history/history"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 3
  namespace = local.namespace
```
See **mem-gateway** for an explanation of these variables.

```
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
```
**qos_limits_cpu/qos_limits_memory** -> QoS class: Burstable.
See **mem-gateway** for an explanation of these variables.

```
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
```
See **mem-gateway** for an explanation of these variables.
***
<br>

# Metadata (mem-metadata)

It records details and metadata about each video.

## Code
**`mem-metadata` microservice (index.js).**
- It uses the `MongoDB` server to store the data in the `metadata` database.
- It subscribes to the `uploaded queue` of `RabbitMQ` to receive `uploaded messages`.
- The *metadata* microservice receives messages from the *video-upload* microservice, and it records them in its database.

**`mem-metadata` module (pri-microservices.tf).**
```
module "mem-metadata" {
  source = "./modules/pri-microservice"
  dir_name = "../../mem-metadata/metadata"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 3
  namespace = local.namespace
```
See **mem-gateway** for an explanation of these variables.

```
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
```
**qos_limits_cpu/qos_limits_memory** -> QoS class: Burstable.
See **mem-gateway** for an explanation of these variables.

```
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
See **mem-gateway** for an explanation of these variables.
***
<br>

# MongoDB (mem-mongodb)

A **single** instance of `MongoDB`, a `NoSQL` database, is used for the application.

## Code
**`mem-mongodb` microservice.**
- Each microservice has its own private database; the databases are hosted on a shared server.

**`mem-mongodb` module (pub-microservices.tf).**
```
module "mem-mongodb" {
  source = "./modules/pub-microservice"
  app_name = var.app_name
  app_version = var.app_version
  image_tag = "mongo:4.2.8"
  # image_tag = "rhscl/mongodb-36-rhel7"
  namespace = local.namespace
```
**image_tag** -> The image to use.
See **mem-gateway** for an explanation of these variables.

```
  /*
  Limits and request for CPU resources are measured in millicores. If the container needs one full
  core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the value of
  '250m.'
  */
  qos_limits_cpu = "400m"
  #qos_limits_memory = "1Gi"
  qos_limits_memory = "500Mi"
```
See **mem-gateway** for an explanation of these variables.

```
  pvc_name = "mongodb-pvc"
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "5Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  #pvc_storage_class_name = "ibmc-s3fs-standard-regional"
  #bucket_name = var.bucket_name
  #private_endpoint = var.private_endpoint
  #api_key = var.api_key
  #service_instance_id = var.service_instance_id
```
Persistent Volume Claim (pvc).

```
  service_name = "mem-mongodb"
  service_port = 27017
  service_target_port = 27017
}
```
See **mem-gateway** for an explanation of these variables.
***
<br>

# RabbitMQ (mem-rabbitmq)

A **single** instance of `RabbitMQ` is used for the application.

#### `Note`
By default, the `guest` user is prohibited from connecting from remote hosts; it can only connect over a loopback interface (i.e. localhost). This applies to connections regardless of the protocol. Any other users will not (by default) be restricted in this way. It is possible to allow the guest user to connect from a remote host by setting the loopback_users configuration to none. See rabbitmq.conf.

## Code
**`mem-rabbitmq` microservice.**
- The RabbitMQ server contains multiple queues with different names.

**`mem-rabbitmq` module (pri-microservices.tf).**
```
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
```
See **mem-mongodb** for an explanation of these variables.

```
  qos_limits_cpu = "400m"
  qos_limits_memory = "300Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
```
See **mem-mongodb** for an explanation of these variables.

```
  service_name = "mem-rabbitmq"
  service_port = 5672
  service_target_port = 5672
}
```
See **mem-gateway** for an explanation of these variables.
***
<br>

# Video-Storage (mem-video-storage)

It stores and retrieves videos from an external cloud storage.

#### `Note`
IBM's Cloud Object Storage (COS) is `S3 (Simple Storage Service)` compatible and can, thus, be used with any S3-compatible tooling. The fundamental unit of object storage is called a `bucket`.

## Code
**`mem-video-storage` microservice.**
- An abstraction of the file storage provider. One advantage of this architecture (separation of concerns and single responsibility principle) is that the video storage microservice can be easily swapped out and be replaced with an alternative.

**`mem-video-storage` module.**
```
module "mem-video-storage" {
  source = "./modules/pri-microservice"
  dir_name = "../../mem-video-storage/video-storage"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 3
  namespace = local.namespace
```
See **mem-gateway** for an explanation of these variables.

```
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
    # With HMAC
    # AUTHENTICATION_TYPE: "hmac"
    # REGION: var.region1
    # ACCESS_KEY_ID: var.access_key_id
    # SECRET_ACCESS_KEY: var.secret_access_key
    # ENDPOINT: var.public_endpoint
    #
    MAX_RETRIES: 20
  }
```
Without and with *HMAC*. *Uncomment* the desired *authentication type* and *comment* the other type.<br>
See **mem-gateway** for an explanation of these variables.

```
  service_name = "mem-video-storage"
}
```
See **mem-gateway** for an explanation of these variables.
***
<br>

# Video-Streaming (mem-video-streaming)

It streams videos from storage to be watched by the user.

## Code
**`mem-video-streaming` microservice.**
- It receives requests from the gateway.
- It forwards the requests to the video storage microservice.
- It sends `viewed messages` to `RabbbitMQ`.

**`mem-video-streaming` module.**
```
module "mem-video-streaming" {
  source = "./modules/pri-microservice"
  dir_name = "../../mem-video-streaming/video-streaming"
  app_name = var.app_name
  app_version = var.app_version
  namespace = local.namespace
  replicas = 3
```
See **mem-gateway** for an explanation of these variables.

```
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
```
See **mem-gateway** for an explanation of these variables.

```
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
See **mem-gateway** for an explanation of these variables.
***
<br>

# Video-Upload (mem-video-upload)

It uploads the videos to storage.

## Code
**`mem-video-upload` microservice.**
- It receives requests from the gateway.
- It forwards the requests to the video storage microservice.
- It sends `uploaded messages` to `RabbbitMQ`.

**`mem-video-upload` module.**
```
module "mem-video-upload" {
  source = "./modules/pri-microservice"
  dir_name = "../../mem-video-upload/video-upload"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 3
  namespace = local.namespace
```
See **mem-gateway** for an explanation of these variables.

```
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
```
See **mem-gateway** for an explanation of these variables.

```
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
See **mem-gateway** for an explanation of these variables.
***
<br>
