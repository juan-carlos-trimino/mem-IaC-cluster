/*
module "ms-rabbitmq" {
  # Specify the location of the module, which contains the file main.tf.
  source = "./modules/pub-microservice"
  # Set input variables to configure the microservice module for the ms-gateway.
  app_name = var.app_name
  app_version = var.app_version
  # This image has the RabbitMQ dashboard.
  # image_tag = "rabbitmq:3.9.7-management-alpine"
  image_tag = "rabbitmq:3.9.7-alpine"
  namespace = local.namespace
  service_name = "mem-rabbitmq"
  service_port = 5672
  service_target_port = 5672
}
*/

/***
# Deployment.
module "mem-rabbitmq" {
  # Specify the location of the module, which contains the file main.tf.
  source = "./modules/microservice-rabbitmq-deploy"
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

# StatefulSet.
module "mem-rabbitmq" {
  source = "./modules/microservice-rabbitmq-stateful"
  dir_name = "../../mem-rabbitmq/rabbitmq"
  app_name = var.app_name
  app_version = var.app_version
  path_rabbitmq_files = "./utility-files/rabbitmq"
  #
  rabbitmq_erlang_cookie = var.rabbitmq_erlang_cookie
  #
  publish_not_ready_addresses = true
  namespace = local.namespace
  replicas = 3
  # Limits and request for CPU resources are measured in millicores. If the container needs one full
  # core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the value of
  # '250m.'
  qos_limits_cpu = "400m"
  qos_limits_memory = "300Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "5Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  service_name = "mem-rabbitmq"
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
    RABBITMQ_CONFIG_FILE = "/config/rabbitmq"
  }
}
