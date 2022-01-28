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

/*
# Deployment.
module "mem-mongodb" {
  source = "./modules/microservice-mongodb-deploy"
  app_name = var.app_name
  app_version = var.app_version
  image_tag = "mongo:5.0"
  namespace = kubernetes_namespace.ns.metadata[0].name
  # namespace = local.namespace
  replicas = 3
  # Limits and request for CPU resources are measured in millicores. If the container needs one full
  # core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the value of
  # '250m.'
  qos_limits_cpu = "400m"
  #qos_limits_memory = "1Gi"
  qos_limits_memory = "500Mi"
  pvc_name = "mongodb-pvc"
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "25Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  service_name = "mem-mongodb"
  service_port = 27017
  service_target_port = 27017
  env = {
    # MONGO_INITIAL_PRIMARY_HOST = "mem-mongodb-0.mem-mongodb.${var.app_name}.svc.cluster.local"
    # MONGO_ENABLE_IPV6 = "no"
  }
}
*/

# Stateful.
module "mem-mongodb" {
  source = "./modules/microservice-mongodb-stateful"
  app_name = var.app_name
  app_version = var.app_version
  image_tag = "mongo:5.0"
  mongodb_files = "./utility-files/mongodb"
  #
  mongodb_database = var.mongodb_database
  mongodb_root_username = var.mongodb_root_username
  mongodb_root_password = var.mongodb_root_password
  mongodb_username = var.mongodb_username
  mongodb_password = var.mongodb_password
  #
  publish_not_ready_addresses = true
  namespace = kubernetes_namespace.ns.metadata[0].name
  # namespace = local.namespace
  replicas = 3
  # Limits and request for CPU resources are measured in millicores. If the container needs one full
  # core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the value of
  # '250m.'
  qos_limits_cpu = "400m"
  #qos_limits_memory = "1Gi"
  qos_limits_memory = "500Mi"
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "25Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  service_name = "mem-mongodb"
  service_port = 27017
  service_target_port = 27017
  env = {
    MONGO_INITIAL_PRIMARY_HOST = "mem-mongodb-0.mem-mongodb.${var.app_name}.svc.cluster.local"
    MONGO_ENABLE_IPV6 = "no"
    # MONGODB_ADMIN_PASSWORD = "jct123"
  #   MONGODB_USER = "guest"
  #   MONGODB_PASSWORD = "guest"
  #   #MONGODB_DATABASE = "history"
  #   MONGODB_DATABASE = "metadata"
 #   ME_CONFIG_MONGODB_ENABLE_ADMIN = true
  }
}
