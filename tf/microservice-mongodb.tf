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
module "mem-mongodb" {
  source = "./modules/microservice-mongodb-deploy"
  app_name = var.app_name
  app_version = var.app_version
  image_tag = "mongo:5.0"
  namespace = kubernetes_namespace.ns.metadata[0].name
  # namespace = local.namespace
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
  # env = {
  # }
}
***/

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
  source = "./modules/microservice-mongodb-stateful"
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
