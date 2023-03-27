# $ terraform init
# $ terraform apply -var="app_version=1.0.0" -auto-approve
# $ terraform apply -var="app_version=1.0.0" -var="k8s_manifest_crd=false" -auto-approve
# $ terraform destroy -var="app_version=1.0.0" -auto-approve
# $ kubectl get all -n memories
locals {
  namespace = kubernetes_namespace.ns.metadata[0].name
  cr_login_server = "docker.io"
  db_metadata = "metadata"
  db_history = "history"
  ###########
  # Traefik #
  ###########
  traefik_secret_cert_name = "le-secret-cert"
  issuer_name = "le-acme-issuer"
  tls_store = "default"
  tls_options = "tlsoptions"
  ##################
  # Ingress Routes #
  ##################
  ingress_route = "mem-ingress-route"
  ###############
  # Middlewares #
  ###############
  middleware_compress = "mem-mw-compress"
  middleware_rate_limit = "mem-mw-rate-limit"
  middleware_error_page = "mem-mw-error-page"
  middleware_gateway_basic_auth = "mem-mw-gateway-basic-auth"
  middleware_dashboard_basic_auth = "mem-mw-dashboard-basic-auth"
  middleware_kibana_basic_auth = "mem-mw-kibana-basic-auth"
  middleware_rabbitmq1 = "mem-mw-rabbitmq-basic-auth"
  middleware_rabbitmq2 = "mem-mw-rabbitmq-strip-prefix"
  middleware_security_headers = "mem-mw-security-headers"
  middleware_redirect_https = "mem-mw-redirect-https"
  #################
  # Elasticsearch #
  #################
  es_issuer = "es-selfsigned-issuer"
  es_secret_cert_name = "es-secret-cert"
  es_configmap = "es-config"
  es_service_account = "es-service-account"
  ####################
  # Name of Services #
  ####################
  svc_finance = "fin-finance"
  svc_error_page = "mem-error-page"
  svc_gateway = "mem-gateway"
  svc_history = "mem-history"
  svc_metadata = "mem-metadata"
  svc_mongodb = "mem-mongodb"
  svc_rabbitmq = "mem-rabbitmq"
  svc_video_storage = "mem-video-storage"
  svc_video_streaming = "mem-video-streaming"
  svc_video_upload = "mem-video-upload"
  svc_elasticsearch_headless = "mem-elasticsearch-headless"
  svc_elasticsearch_master = "mem-elasticsearch-master"
  svc_elasticsearch_data = "mem-elasticsearch-data"
  svc_elasticsearch_client = "mem-elasticsearch-client"
  svc_kibana = "mem-kibana"
  svc_logstash = "mem-logstash"
  svc_filebeat = "mem-filebeat"
  ############
  # Services #
  ############
  # DNS translates hostnames to IP addresses; the container name is the hostname. When using Docker
  # and Docker Compose, DNS works automatically.
  # In K8s, a service makes the deployment accessible by other containers via DNS.
  svc_dns_error_page = "${local.svc_error_page}.${local.namespace}.svc.cluster.local"
  svc_dns_gateway = "${local.svc_gateway}.${local.namespace}.svc.cluster.local"
  svc_dns_history = "${local.svc_history}.${local.namespace}.svc.cluster.local"
  svc_dns_metadata = "${local.svc_metadata}.${local.namespace}.svc.cluster.local"
  svc_dns_db = "mongodb://${local.svc_mongodb}.${local.namespace}.svc.cluster.local:27017"
  # svc_dns_db = "mongodb://${var.mongodb_username}:${var.mongodb_password}@mem-mongodb.${local.namespace}.svc.cluster.local:27017"
  # Stateful stuff
  # svc_dns_db = "mongodb://mem-mongodb-0.mem-mongodb.${local.namespace}.svc.cluster.local,mem-mongodb-1.mem-mongodb.${local.namespace}.svc.cluster.local,mem-mongodb-2.mem-mongodb.${local.namespace}.svc.cluster.local:27017"
  #
  # By default, the guest user is prohibited from connecting from remote hosts; it can only connect
  # over a loopback interface (i.e. localhost). This applies to connections regardless of the
  # protocol. Any other users will not (by default) be restricted in this way.
  #
  # It is possible to allow the guest user to connect from a remote host by setting the
  # loopback_users configuration to none. (See rabbitmq.conf)
  svc_dns_rabbitmq = "amqp://${var.rabbitmq_default_user}:${var.rabbitmq_default_pass}@${local.svc_rabbitmq}-headless.${local.namespace}.svc.cluster.local:5672"
  svc_dns_video_storage = "${local.svc_video_storage}.${local.namespace}.svc.cluster.local"
  svc_dns_video_streaming = "${local.svc_video_streaming}.${local.namespace}.svc.cluster.local"
  svc_dns_video_upload = "${local.svc_video_upload}.${local.namespace}.svc.cluster.local"
  svc_dns_kibana = "${local.svc_kibana}.${local.namespace}.svc.cluster.local:5601"
  //
  svc_dns_finance = "${local.svc_finance}.${local.namespace}.svc.cluster.local"
}

###################################################################################################
# traefik                                                                                         #
###################################################################################################
/*** traefik
# kubectl get pod,middleware,ingressroute,svc -n memories
# kubectl get all -l "app.kubernetes.io/instance=traefik" -n memories
# kubectl get all -l "app=memories" -n memories
module "traefik" {
  source = "./modules/traefik/traefik"
  app_name = var.app_name
  namespace = local.namespace
  chart_version = "10.24.0"
  api_auth_token = var.traefik_dns_api_token
  service_name = "mem-traefik"
}

module "middleware-gateway-basic-auth" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/middlewares/middleware-gateway-basic-auth"
  app_name = var.app_name
  namespace = local.namespace
  traefik_gateway_username = var.traefik_gateway_username
  traefik_gateway_password = var.traefik_gateway_password
  service_name = local.middleware_gateway_basic_auth
}

module "middleware-dashboard-basic-auth" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/middlewares/middleware-dashboard-basic-auth"
  app_name = var.app_name
  namespace = local.namespace
  # While the dashboard in itself is read-only, it is good practice to secure access to it.
  traefik_dashboard_username = var.traefik_dashboard_username
  traefik_dashboard_password = var.traefik_dashboard_password
  service_name = local.middleware_dashboard_basic_auth
}

module "middleware-kibana-basic-auth" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/middlewares/middleware-kibana-basic-auth"
  app_name = var.app_name
  namespace = local.namespace
  kibana_username = var.kibana_username
  kibana_password = var.kibana_password
  service_name = local.middleware_kibana_basic_auth
}

module "middleware-rabbitmq" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/middlewares/middleware-rabbitmq-basic-auth"
  app_name = var.app_name
  namespace = local.namespace
  traefik_rabbitmq_username = var.traefik_rabbitmq_username
  traefik_rabbitmq_password = var.traefik_rabbitmq_password
  service_name1 = local.middleware_rabbitmq1
  service_name2 = local.middleware_rabbitmq2
}

module "middleware-compress" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/middlewares/middleware-compress"
  app_name = var.app_name
  namespace = local.namespace
  service_name = local.middleware_compress
}

module "middleware-rate-limit" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/middlewares/middleware-rate-limit"
  app_name = var.app_name
  namespace = local.namespace
  average = 6
  period = "1m"
  burst = 12
  service_name = local.middleware_rate_limit
}

module "middleware-security-headers" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/middlewares/middleware-security-headers"
  app_name = var.app_name
  namespace = local.namespace
  service_name = local.middleware_security_headers
}

module "middleware-redirect-https" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/middlewares/middleware-redirect-https"
  app_name = var.app_name
  namespace = local.namespace
  service_name = local.middleware_redirect_https
}

module "tlsstore" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/tlsstore"
  app_name = var.app_name
  namespace = "default"
  secret_name = local.traefik_secret_cert_name
  service_name = local.tls_store
}

module "tlsoptions" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/tlsoptions"
  app_name = var.app_name
  namespace = local.namespace
  service_name = local.tls_options
}

module "ingress-route" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/ingress-route"
  app_name = var.app_name
  namespace = local.namespace
  tls_store = local.tls_store
  tls_options = local.tls_options
  middleware_rate_limit = local.middleware_rate_limit
  middleware_compress = local.middleware_compress
  middleware_gateway_basic_auth = local.middleware_gateway_basic_auth
  middleware_dashboard_basic_auth = local.middleware_dashboard_basic_auth
  middleware_security_headers = local.middleware_security_headers
  middleware_kibana_basic_auth = local.middleware_kibana_basic_auth
  svc_finance = local.svc_finance
  svc_gateway = local.svc_gateway
  svc_kibana = local.svc_kibana
  secret_name = local.traefik_secret_cert_name
  issuer_name = local.issuer_name
  # host_name = "169.46.98.220.nip.io"
  # host_name = "memories.mooo.com"
  host_name = "trimino.xyz"
  service_name = local.ingress_route
}
***/ # traefik

###################################################################################################
# cert manager                                                                                    #
###################################################################################################
/*** cert manager
module "cert-manager" {
  source = "./modules/traefik/cert-manager/cert-manager"
  namespace = local.namespace
  chart_version = "1.9.1"
  service_name = "mem-cert-manager"
}

module "acme-issuer" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/cert-manager/acme-issuer"
  app_name = var.app_name
  namespace = local.namespace
  issuer_name = local.issuer_name
  acme_email = var.traefik_le_email
  # Let's Encrypt has two different services, one for staging (letsencrypt-staging) and one for
  # production (letsencrypt-prod).
  acme_server = "https://acme-staging-v02.api.letsencrypt.org/directory"
  # acme_server = "https://acme-v02.api.letsencrypt.org/directory"
  dns_names = ["trimino.xyz", "www.trimino.xyz"]
  # Digital Ocean token requires base64 encoding.
  traefik_dns_api_token = var.traefik_dns_api_token
}

module "certificate" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/cert-manager/certificates"
  app_name = var.app_name
  namespace = local.namespace
  issuer_name = local.issuer_name
  certificate_name = "le-cert"
  # The A record maps a name to one or more IP addresses when the IP are known and stable.
  # The CNAME record maps a name to another name. It should only be used when there are no other
  # records on that name.
  # common_name = "trimino.xyz"
  dns_names = ["trimino.xyz", "www.trimino.xyz"]
  secret_name = local.traefik_secret_cert_name
}
***/ # cert manager

###################################################################################################
# whoami                                                                                          #
###################################################################################################
/*** # web service app for testing Traefik
module "whoiam" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/traefik/whoami"
  app_name = var.app_name
  app_version = var.app_version
  namespace = local.namespace
  service_name = "mem-whoami"
}
***/ # Web service

###################################################################################################
# elk                                                                                             #
###################################################################################################
/*** elk cert-manager
module "elk-issuer" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/elk/cert-manager/issuer"
  app_name = var.app_name
  namespace = local.namespace
  issuer_name = local.es_issuer
}

module "elk-certificate" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/elk/cert-manager/certificates"
  app_name = var.app_name
  namespace = local.namespace
  issuer_name = local.es_issuer
  certificate_name = "elk-cert"
  # The A record maps a name to one or more IP addresses when the IP are known and stable.
  # The CNAME record maps a name to another name. It should only be used when there are no other
  # records on that name.
  # common_name = "trimino.xyz"
  dns_names = [
    local.svc_elasticsearch_client,
    "${local.svc_elasticsearch_client}.${local.namespace}",
    "${local.svc_elasticsearch_client}.${local.namespace}.svc.cluster.local"
  ]
  secret_name = local.es_secret_cert_name
}
***/
# /*** elk
module "mem-elasticsearch-master" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/elk/elasticsearch/es-master"
  app_name = var.app_name
  image_tag = "docker.elastic.co/elasticsearch/elasticsearch:8.6.0"
  image_pull_policy = "IfNotPresent"
  publish_not_ready_addresses = true
  namespace = local.namespace
  replicas = 3
  # The default is to deploy all pods serially. By setting this to parallel, all pods are started
  # at the same time when bootstrapping the cluster.
  pod_management_policy = "Parallel"
  # Limits and requests for CPU resources are measured in millicores. If the container needs one
  # full core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the
  # value of '250m.'
  qos_limits_cpu = "1000m"
  qos_limits_memory = "2Gi"
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "2Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  env = {
    "node.roles": "[master]"
    ES_JAVA_OPTS: "-Xms1g -Xmx1g"
    "discovery.seed_hosts": <<EOL
      "${local.svc_elasticsearch_master}-0.${local.svc_elasticsearch_headless}.${local.namespace}.svc.cluster.local,
       ${local.svc_elasticsearch_master}-1.${local.svc_elasticsearch_headless}.${local.namespace}.svc.cluster.local,
       ${local.svc_elasticsearch_master}-2.${local.svc_elasticsearch_headless}.${local.namespace}.svc.cluster.local"
    EOL
    "cluster.initial_master_nodes": <<EOL
      "${local.svc_elasticsearch_master}-0,
       ${local.svc_elasticsearch_master}-1,
       ${local.svc_elasticsearch_master}-2"
    EOL
  }
  es_configmap = local.es_configmap
  es_service_account = local.es_service_account
  transport_service_port = 9300
  transport_service_target_port = 9300
  service_name_headless = local.svc_elasticsearch_headless
  service_name = local.svc_elasticsearch_master
}

module "mem-elasticsearch-data" {
  count = var.k8s_manifest_crd ? 0 : 1
  depends_on = [
    module.mem-elasticsearch-master
  ]
  source = "./modules/elk/elasticsearch/es-data"
  app_name = var.app_name
  image_tag = "docker.elastic.co/elasticsearch/elasticsearch:8.6.0"
  image_pull_policy = "IfNotPresent"
  publish_not_ready_addresses = true
  namespace = local.namespace
  replicas = 2
  pod_management_policy = "Parallel"
  qos_limits_cpu = "3000m"
  qos_limits_memory = "8Gi"
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "50Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  env = {
    "node.roles": "[data]"
    ES_JAVA_OPTS: "-Xms4g -Xmx4g"
    "discovery.seed_hosts": <<EOL
      "${local.svc_elasticsearch_master}-0.${local.svc_elasticsearch_headless}.${local.namespace}.svc.cluster.local,
       ${local.svc_elasticsearch_master}-1.${local.svc_elasticsearch_headless}.${local.namespace}.svc.cluster.local,
       ${local.svc_elasticsearch_master}-2.${local.svc_elasticsearch_headless}.${local.namespace}.svc.cluster.local"
    EOL
    "cluster.initial_master_nodes": <<EOL
      "${local.svc_elasticsearch_master}-0,
       ${local.svc_elasticsearch_master}-1,
       ${local.svc_elasticsearch_master}-2"
    EOL
  }
  es_configmap = local.es_configmap
  es_service_account = local.es_service_account
  transport_service_port = 9300
  transport_service_target_port = 9300
  service_name_headless = local.svc_elasticsearch_headless
  service_name = local.svc_elasticsearch_data
}

module "mem-elasticsearch-client" {
  count = var.k8s_manifest_crd ? 0 : 1
  depends_on = [
    module.mem-elasticsearch-data
  ]
  source = "./modules/elk/elasticsearch/es-client"
  app_name = var.app_name
  image_tag = "docker.elastic.co/elasticsearch/elasticsearch:8.6.0"
  image_pull_policy = "IfNotPresent"
  namespace = local.namespace
  replicas = 2
  qos_limits_cpu = "1000m"
  qos_limits_memory = "4Gi"
  env = {
    "node.roles": "[remote_cluster_client]"  # A coordinating node.
    ES_JAVA_OPTS: "-Xms2g -Xmx2g"
    "discovery.seed_hosts": <<EOL
      "${local.svc_elasticsearch_master}-0.${local.svc_elasticsearch_headless}.${local.namespace}.svc.cluster.local,
       ${local.svc_elasticsearch_master}-1.${local.svc_elasticsearch_headless}.${local.namespace}.svc.cluster.local,
       ${local.svc_elasticsearch_master}-2.${local.svc_elasticsearch_headless}.${local.namespace}.svc.cluster.local"
    EOL
  }
  es_configmap = local.es_configmap
  # Port 9200 for the HTTP API.
  http_service_port = 9200
  http_service_target_port = 9200
  # Port 9300 to communicate with the other nodes of the cluster.
  transport_service_port = 9300
  transport_service_target_port = 9300
  service_name = local.svc_elasticsearch_client
}

module "mem-kibana" {
  count = var.k8s_manifest_crd ? 0 : 1
  depends_on = [
    module.mem-elasticsearch-client
  ]
  source = "./modules/elk/kibana"
  app_name = var.app_name
  image_tag = "docker.elastic.co/kibana/kibana:8.6.0"
  image_pull_policy = "IfNotPresent"
  namespace = local.namespace
  replicas = 1
  qos_requests_cpu = "200m"
  qos_requests_memory = "500Mi"
  qos_limits_cpu = "750m"
  qos_limits_memory = "1Gi"
  env = {
    # https://github.com/elastic/kibana/blob/main/config/kibana.yml
    # https://www.elastic.co/guide/en/kibana/current/settings.html
    # This setting specifies the host of the back end server. To allow remote users to connect, set
    # the value to the IP address or DNS name of the Kibana server.
    "server.host": local.svc_dns_kibana
    # Kibana is served by a back end server. This setting specifies the port to use.
    "server.port": 5601
    # The URLs of the Elasticsearch instances to use for all your queries.
    "elasticsearch.hosts": "[\"http://${local.svc_elasticsearch_client}:9200\"]"
    ELASTICSEARCH_HOSTS: "[\"http://${local.svc_elasticsearch_client}:9200\"]"
    SERVER_BASEPATH: "/kibana"
    SERVER_REWRITEBASEPATH: true
    # X-Pack settings.
    "xpack.license.self_generated.type": "basic"
    "xpack.security.enabled": false
    "xpack.security.transport.ssl.enabled": false
    "xpack.security.transport.ssl.verification_mode": "none"
    "xpack.security.http.ssl.enabled": false
    # Disable unused xpack features.
    "xpack.reporting.enabled": false
    "xpack.ml.enabled": false
    "xpack.graph.enabled": false
  }
  service_port = 5601
  service_target_port = 5601
  service_name = local.svc_kibana
}

module "mem-logstash" {
  count = var.k8s_manifest_crd ? 0 : 1
  depends_on = [
    module.mem-kibana
  ]
  source = "./modules/elk/logstash"
  app_name = var.app_name
  image_tag = "docker.elastic.co/logstash/logstash:8.6.0"
  image_pull_policy = "IfNotPresent"
  namespace = local.namespace
  replicas = 1
  qos_limits_cpu = "2500m"
  qos_limits_memory = "4Gi"
  qos_requests_cpu = "800m"
  qos_requests_memory = "4Gi"
  es_hosts = "http://${local.svc_elasticsearch_client}:9200"
  beats_service_port = 5044
  beats_service_target_port = 5044
  logstash_service_port = 9600
  logstash_service_target_port = 9600
  service_name = local.svc_logstash
}

# Filebeat is the agent that ships logs to Logstash.
module "mem-filebeat" {
  count = var.k8s_manifest_crd ? 0 : 1
  depends_on = [
    module.mem-logstash
  ]
  source = "./modules/elk/filebeat"
  app_name = var.app_name
  image_tag = "docker.elastic.co/beats/filebeat:8.6.0"
  image_pull_policy = "IfNotPresent"
  namespace = local.namespace
  host_network = true
  util_path = "./modules/elk/filebeat/util"
  # Limits and requests for CPU resources are measured in millicores. If the container needs one
  # full core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the
  # value of '250m.'
  qos_requests_cpu = "500m"
  qos_requests_memory = "100Mi"
  qos_limits_cpu = "600m"
  qos_limits_memory = "200Mi"
  logstash_hosts = "${local.svc_logstash}:5044"
  kibana_host = "http://${local.svc_kibana}:5601"
  service_name = local.svc_filebeat
}
# ***/  # elk

###################################################################################################
# mongodb                                                                                         #
###################################################################################################
# /*** mongodb - deployment goodxxxx
# Deployment.
module "mem-mongodb" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/mongodb-deploy"
  app_name = var.app_name
  app_version = var.app_version
  image_tag = "mongo:5.0"
  namespace = local.namespace
  replicas = 1
  # Limits and requests for CPU resources are measured in millicores. If the container needs one
  # full core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the
  # value of '250m.'
  qos_limits_cpu = "400m"
  qos_limits_memory = "1Gi"
  # qos_limits_memory = "500Mi"
  pvc_name = "mongodb-pvc"
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "25Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  service_name = local.svc_mongodb
  service_port = 27017
  service_target_port = 27017
}
# ***/  # mongodb - deployment

/*** mongodb - statefulset active
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
  # Limits and requests for CPU resources are measured in millicores. If the container needs one
  # full core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the
  # value of '250m.'
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
***/  # mongodb - statefulset

###################################################################################################
# rabbitmq                                                                                        #
###################################################################################################
/*** rabbitmq - deployment
# Deployment.
module "mem-rabbitmq" {
  # Specify the location of the module, which contains the file main.tf.
  source = "./modules/rabbitmq-deploy"
  # dir_name = "../../${local.svc_rabbitmq}/rabbitmq"
  app_name = var.app_name
  app_version = var.app_version
  # This image has the RabbitMQ dashboard.
  image_tag = "rabbitmq:3.9.15-management-alpine"
  image_pull_policy = "IfNotPresent"
  # image_tag = "rabbitmq:3.9.7-alpine"
  # path_rabbitmq_files = "./utility-files/rabbitmq"
  path_rabbitmq_files = "./modules/rabbitmq-statefulset/util"
  namespace = local.namespace
  qos_limits_cpu = "400m"
  qos_limits_memory = "300Mi"
  rabbitmq_erlang_cookie = var.rabbitmq_erlang_cookie
  rabbitmq_default_pass = var.rabbitmq_default_pass
  rabbitmq_default_user = var.rabbitmq_default_user
  # cr_login_server = local.cr_login_server
  # cr_username = var.cr_username
  # cr_password = var.cr_password
  amqp_service_port = 5672
  amqp_service_target_port = 5672
  # HTTP API clients, management UI, and rabbitmqadmin, without and with TLS (only if the
  # management plugin is enabled).
  mgmt_service_port = 15672
  mgmt_service_target_port = 15672
  service_name = local.svc_rabbitmq
}
***/  # rabbitmq - deployment

# /*** rabbitmq - statefulset goodxxcxx
# StatefulSet.
module "mem-rabbitmq" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/rabbitmq-statefulset"
  app_name = var.app_name
  app_version = var.app_version
  # This image has the RabbitMQ dashboard.
  image_tag = "rabbitmq:3.9.7-management-alpine"
  image_pull_policy = "IfNotPresent"
  path_rabbitmq_files = "./modules/rabbitmq-statefulset/util"
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
  replicas = 1
  # Limits and requests for CPU resources are measured in millicores. If the container needs one
  # full core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the
  # value of '250m.'
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
  service_name = local.svc_rabbitmq
}
# ***/  # rabbitmq - statefulset

###################################################################################################
# Application                                                                                     #
###################################################################################################
# /*** app
module "mem-gateway" {
  count = var.k8s_manifest_crd ? 0 : 1
  # Specify the location of the module, which contains the file main.tf.
  source = "./modules/deployment"
  dir_name = "../../${local.svc_gateway}/gateway"
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
    SVC_NAME: local.svc_gateway
    SVC_DNS_METADATA: local.svc_dns_metadata
    SVC_DNS_HISTORY: local.svc_dns_history
    SVC_DNS_VIDEO_UPLOAD: local.svc_dns_video_upload
    SVC_DNS_VIDEO_STREAMING: local.svc_dns_video_streaming
    SVC_DNS_KIBANA: local.svc_dns_kibana
    APP_NAME_VER: "${var.app_name} ${var.app_version}"
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
  service_name = local.svc_gateway
  # service_type = "LoadBalancer"
}

module "mem-history" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/deployment"
  dir_name = "../../${local.svc_history}/history"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 1
  namespace = local.namespace
  qos_requests_memory = "50Mi"
  qos_limits_memory = "100Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  env = {
    SVC_NAME: local.svc_history
    SVC_DNS_RABBITMQ: local.svc_dns_rabbitmq
    SVC_DNS_DB: local.svc_dns_db
    DB_NAME: local.db_history
    APP_NAME_VER: "${var.app_name} ${var.app_version}"
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
  service_name = local.svc_history
}

module "mem-metadata" {
  count = var.k8s_manifest_crd ? 0 : 1
  depends_on = [
    module.mem-mongodb
  ]
  source = "./modules/deployment"
  dir_name = "../../${local.svc_metadata}/metadata"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 1
  namespace = local.namespace
  qos_requests_memory = "50Mi"
  qos_limits_memory = "100Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  env = {
    SVC_NAME: local.svc_metadata
    SVC_DNS_RABBITMQ: local.svc_dns_rabbitmq
    SVC_DNS_DB: local.svc_dns_db
    DB_NAME: local.db_metadata
    APP_NAME_VER: "${var.app_name} ${var.app_version}"
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
  service_name = local.svc_metadata
}

module "mem-video-storage" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/deployment"
  dir_name = "../../${local.svc_video_storage}/video-storage"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 1
  namespace = local.namespace
  qos_limits_cpu = "300m"
  qos_limits_memory = "500Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  env = {
    SVC_NAME: local.svc_video_storage
    BUCKET_NAME: var.bucket_name
    # Without HMAC.
    AUTHENTICATION_TYPE: "iam"
    API_KEY: var.storage_api_key
    SERVICE_INSTANCE_ID: var.resource_instance_id
    ENDPOINT: var.public_endpoint
    # With HMAC.
    # AUTHENTICATION_TYPE: "hmac"
    # REGION: var.region1
    # ACCESS_KEY_ID: var.access_key_id
    # SECRET_ACCESS_KEY: var.secret_access_key
    # ENDPOINT: var.public_endpoint
    #
    APP_NAME_VER: "${var.app_name} ${var.app_version}"
    MAX_RETRIES: 20
  }
  service_name = local.svc_video_storage
}

module "mem-video-streaming" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/deployment"
  dir_name = "../../${local.svc_video_streaming}/video-streaming"
  app_name = var.app_name
  app_version = var.app_version
  namespace = local.namespace
  replicas = 1
  qos_requests_memory = "150Mi"
  qos_limits_memory = "300Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  env = {
    SVC_NAME: local.svc_video_streaming
    SVC_DNS_RABBITMQ: local.svc_dns_rabbitmq
    SVC_DNS_VIDEO_STORAGE: local.svc_dns_video_storage
    APP_NAME_VER: "${var.app_name} ${var.app_version}"
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
  service_name = local.svc_video_streaming
}

module "mem-video-upload" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/deployment"
  dir_name = "../../${local.svc_video_upload}/video-upload"
  app_name = var.app_name
  app_version = var.app_version
  replicas = 1
  namespace = local.namespace
  qos_requests_memory = "150Mi"
  qos_limits_memory = "300Mi"
  cr_login_server = local.cr_login_server
  cr_username = var.cr_username
  cr_password = var.cr_password
  env = {
    SVC_NAME: local.svc_video_upload
    SVC_DNS_RABBITMQ: local.svc_dns_rabbitmq
    SVC_DNS_VIDEO_STORAGE: local.svc_dns_video_storage
    APP_NAME_VER: "${var.app_name} ${var.app_version}"
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
  service_name = local.svc_video_upload
}
# ***/  # app
/*** #finances

module "fin-finance" {
  count = var.k8s_manifest_crd ? 0 : 1
  # Specify the location of the module, which contains the file main.tf.
  source = "./modules/deployment"
  dir_name = "../../${local.svc_finance}"
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
    SVC_NAME: local.svc_finance
    APP_NAME_VER: "${var.app_name} ${var.app_version}"
    # PORT: "8080"
    MAX_RETRIES: 20
    SERVER = "http://${local.svc_dns_finance}"
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
  service_name = local.svc_finance
  service_type = "LoadBalancer"
}

***/ #finances