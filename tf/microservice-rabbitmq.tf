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

# Deployment.
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

/***
# StatefulSet.
***/
