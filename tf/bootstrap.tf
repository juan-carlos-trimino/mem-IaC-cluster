###########
# traefik #
###########
# The hosts file is used to map domain names (hostnames) to IP addresses. It is a plain-text file
# used by all operating systems including, Linux, Windows, and macOS. The hosts file has priority
# over DNS. When typing in the domain name of a web site to visit, the domain name must be
# translated into its corresponding IP address. The operating system first checks its hosts file
# for the corresponding domain, and if there is no entry for the domain, it will query the
# configured DNS servers to resolve the specified domain name. This affects only the computer on
# which the change is made, rather than how the domain is resolved worldwide. Entries in the hosts
# file have the following format:
#   IPAddress DomainName [DomainAliases]
# The IP address and the domain names should be separated by at least one space or tab. The lines
# starting with '#' are comments and are ignored.
# On Linux, the full path to the file is /etc/hosts.
# On Windows, the full path to the file is C:\Windows\System32\drivers\etc\hosts.
/***CCC
# kubectl get pod,middleware,ingressroute,svc -n memories
# kubectl get all -l "app.kubernetes.io/instance=traefik" -n memories
# kubectl get all -l "app=memories" -n memories
locals {
  middleware_dashboard = "mem-middleware-dashboard"
}

module "traefik" {
  source = "./modules/traefik/traefik"
  app_name = var.app_name
  namespace = local.namespace
  service_name = "mem-traefik"
}

module "middleware-dashboard" {
  source = "./modules/traefik/middlewares/middleware-dashboard"
  app_name = var.app_name
  namespace = local.namespace
  # While the dashboard in itself is read-only, it is good practice to secure access to it.
  traefik_dashboard_username = var.traefik_dashboard_username
  traefik_dashboard_password = var.traefik_dashboard_password
  service_name = local.middleware_dashboard
}

module "ingress-route" {
  source = "./modules/traefik/ingress-route"
  app_name = var.app_name
  namespace = local.namespace
  middleware_dashboard = local.middleware_dashboard
  service_name = "mem-ingress-route"
}
CCC***/




/***
module "issuers" {
  depends_on = [module.cert-manager]
  source = "./modules/cert-manager/issuers"
  namespace = local.namespace
}

module "certificates" {
  depends_on = [module.issuers]
  source = "./modules/cert-manager/certificates"
  namespace = local.namespace
}
***/


###########
# mongodb #
###########
# /***CCC
# Deployment.
module "mem-mongodb" {
  source = "./modules/mongodb-deploy"
  app_name = var.app_name
  app_version = var.app_version
  image_tag = "mongo:5.0"
  namespace = local.namespace
  replicas = 1
  # Limits and request for CPU resources are measured in millicores. If the container needs one full
  # core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the value of
  # '250m.'
  qos_limits_cpu = "400m"
  qos_limits_memory = "1Gi"
  # qos_limits_memory = "500Mi"
  pvc_name = "mongodb-pvc"
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "25Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  service_name = "mem-mongodb"
  service_port = 27017
  service_target_port = 27017
}
# CCC***/
/***
# StatefulSet.
# (1) When a container is started for the first time it will execute files with extensions .sh and
#     .js that are found in /docker-entrypoint-initdb.d. Files will be executed in alphabetical
#     order. .js files will be executed by mongo using the database specified by the
#     MONGO_INITDB_DATABASE variable, if it is present, or 'test' otherwise. You may also switch
#     databases within the .js script.
# (2) mongod does not read a configuration file by default, so the --config option with the path to
#     the configuration file needs to be specified.
module "mem-mongodb" {
  source = "./modules/mongodb-statefulset"
  dir_name = "../../mem-mongodb/mongodb"
  app_name = var.app_name
  app_version = var.app_version
  # image_tag = "mongo:5.0"
  path_mongodb_files = "./utility-files/mongodb"
  #
  mongodb_database = var.mongodb_database
  mongo_initdb_root_username = var.mongo_initdb_root_username
  mongo_initdb_root_password = var.mongo_initdb_root_password
  mongodb_username = var.mongodb_username
  mongodb_password = var.mongodb_password
  #
  publish_not_ready_addresses = true
  namespace = local.namespace
  replicas = 3
  # Limits and request for CPU resources are measured in millicores. If the container needs one full
  # core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the value of
  # '250m.'
  qos_limits_cpu = "400m"
  qos_limits_memory = "1Gi"
  # qos_limits_memory = "500Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "25Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  service_name = "mem-mongodb"
  service_port = 27017
  service_target_port = 27017
  env = {
    MONGO_INITDB_DATABASE = "test"  # 'test' is the default db.
  }
}
***/

############
# rabbitmq #
############
/***
# Deployment.
module "mem-rabbitmq" {
  # Specify the location of the module, which contains the file main.tf.
  source = "./modules/rabbitmq-deploy"
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
***/
# /***CCC
# StatefulSet.
module "mem-rabbitmq" {
  source = "./modules/rabbitmq-statefulset"
  app_name = var.app_name
  app_version = var.app_version
  # This image has the RabbitMQ dashboard.
  image_tag = "rabbitmq:3.9.7-management-alpine"
  imagePullPolicy = "IfNotPresent"
  path_rabbitmq_files = "./utility-files/rabbitmq"
  #
  rabbitmq_erlang_cookie = var.rabbitmq_erlang_cookie
  rabbitmq_default_pass = var.rabbitmq_default_pass
  rabbitmq_default_user = var.rabbitmq_default_user
  #
  publish_not_ready_addresses = true
  namespace = local.namespace
  # Because several features (e.g. quorum queues, client tracking in MQTT) require a consensus
  # between cluster members, odd numbers of cluster nodes are highly recommended: 1, 3, 5, 7
  # and so on.
  replicas = 3
  # Limits and request for CPU resources are measured in millicores. If the container needs one full
  # core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the value of
  # '250m.'
  qos_limits_cpu = "400m"
  qos_limits_memory = "300Mi"
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "5Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  # Used by AMQP 0-9-1 and AMQP 1.0 clients without and with TLS.
  amqp_service_port = 5672
  amqp_service_target_port = 5672
  # HTTP API clients, management UI, and rabbitmqadmin, without and with TLS (only if the
  # management plugin is enabled).
  mgmt_service_port = 15672
  mgmt_service_target_port = 15672
  env = {
    # If a system uses fully qualified domain names (FQDNs) for hostnames, RabbitMQ nodes and CLI
    # tools must be configured to use so called long node names.
    RABBITMQ_USE_LONGNAME = true
    # Override the main RabbitMQ config file location.
    RABBITMQ_CONFIG_FILE = "/config/rabbitmq"
  }
  service_name = "mem-rabbitmq"
}
# CCC***/


