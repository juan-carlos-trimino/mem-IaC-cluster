# $ terraform init
# $ terraform apply -var="app_version=1.0.0" -auto-approve
# $ terraform apply -var="app_version=1.0.0" -var="k8s_manifest_crd=false" -auto-approve
# $ terraform destroy -var="app_version=1.0.0" -auto-approve
locals {
  namespace = kubernetes_namespace.ns.metadata[0].name
  cr_login_server = "docker.io"
  db_metadata = "metadata"
  db_history = "history"
  ###########
  # Traefik #
  ###########
  secret_cert_name = "le-secret-cert"
  # dashboard_secret_cert_name = "le-dashboard-secret-cert"
  issuer_name = "le-acme-issuer"
  tls_store = "default"
  tls_options = "tlsoptions"
  ##################
  # Ingress Routes #
  ##################
  ingress_route = "mem-ingress-route"
  ingress_route_dashboard = "mem-ingress-route-dashboard"
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
  ####################
  # Name of Services #
  ####################
  svc_error_page = "mem-error-page"
  svc_gateway = "mem-gateway"
  svc_history = "mem-history"
  svc_metadata = "mem-metadata"
  svc_mongodb = "mem-mongodb"
  svc_rabbitmq = "mem-rabbitmq"
  svc_video_storage = "mem-video-storage"
  svc_video_streaming = "mem-video-streaming"
  svc_video_upload = "mem-video-upload"
  elasticsearch_cluster_name = "cluster-elk"
  svc_elasticsearch_headless = "mem-elasticsearch-headless"
  svc_elasticsearch_master = "mem-elasticsearch-master"
  svc_elasticsearch_data = "mem-elasticsearch-data"
  svc_elasticsearch_client = "mem-elasticsearch-client"
  svc_kibana = "mem-kibana"
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
  svc_dns_rabbitmq = "amqp://${var.rabbitmq_default_user}:${var.rabbitmq_default_pass}@${local.svc_rabbitmq}.${local.namespace}.svc.cluster.local:5672"
  svc_dns_video_storage = "${local.svc_video_storage}.${local.namespace}.svc.cluster.local"
  svc_dns_video_streaming = "${local.svc_video_streaming}.${local.namespace}.svc.cluster.local"
  svc_dns_video_upload = "${local.svc_video_upload}.${local.namespace}.svc.cluster.local"
  # svc_dns_elasticsearch = "${local.svc_elasticsearch_master}.${local.namespace}.svc.cluster.local:9200"
  svc_dns_kibana = "${local.svc_kibana}.${local.namespace}.svc.cluster.local:5601"
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
  secret_name = local.secret_cert_name
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
  svc_gateway = local.svc_gateway
  svc_kibana = local.svc_kibana
  secret_name = local.secret_cert_name
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
  # acme_server = "https://acme-staging-v02.api.letsencrypt.org/directory"
  acme_server = "https://acme-v02.api.letsencrypt.org/directory"
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
  secret_name = local.secret_cert_name
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
# To connect to a specific pod without going through a service, use the 'port-forward' command.
#
# $ kubectl port-forward <pod-name> <local-port>:<pod-port> -n <namespace>
#
# To connect via a service
#
# $ kubectl port-forward svc/<service-name> <local-port>:<pod-port> -n <namespace>
#
# Once the port forwarder is running, from a different terminal (or web browser) connect to the pod
# through the local port.
#
# From a terminal:
# $ curl http://localhost:<local-port>
#
# From a web browser:
# http://localhost:<local-port>
#
#
# To check the state of the deployment, use the 'port-forward' command.
# For the service:
# $ kubectl port-forward svc/mem-elasticsearch-headless 9200:9200 -n memories
# $ kubectl port-forward svc/mem-elasticsearch 9200:9200 -n memories
#
# From a terminal:
# $ curl http://localhost:9200/_cat/health?v
# Cluster Stats
# $ curl http://localhost:9200/_cluster/stats?human&pretty
# Cluster State
# $ curl http://localhost:9200/_cluster/state?pretty
# Cluster Health
# $ curl http://localhost:9200/_cluster/health?pretty
# Nodes Stats
# $ curl http://localhost:9200/_nodes/stats?pretty
# Specific Node Stats
# $ curl http://localhost:9200/_nodes/mem-elasticsearch-1/stats?pretty
# Index-Only Stats:
# $ curl http://localhost:9200/_nodes/stats/indices?pretty
#
# From a web browser:
# http://localhost:9200/_cat/health?v
# Cluster Stats
# http://localhost:9200/_cluster/stats?human&pretty
# Cluster State
# http://localhost:9200/_cluster/state?pretty
# Cluster Health
# http://localhost:9200/_cluster/health?pretty
# Nodes Stats
# http://localhost:9200/_nodes/stats?pretty
# Specific Node Stats
# http://localhost:9200/_nodes/mem-elasticsearch-1/stats?pretty
# Index-Only Stats:
# http://localhost:9200/_nodes/stats/indices?pretty

# /*** elk
module "mem-elasticsearch-master" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/elk/elasticsearch/es-master"
  app_name = var.app_name
  image_tag = "docker.elastic.co/elasticsearch/elasticsearch:8.4.1"
  imagePullPolicy = "IfNotPresent"
  publish_not_ready_addresses = true
  namespace = local.namespace
  replicas = 3
  # Limits and requests for CPU resources are measured in millicores. If the container needs one
  # full core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the
  # value of '250m.'
  qos_limits_cpu = "1000m"
  qos_requests_cpu = "250m"
  qos_limits_memory = "1Gi"
  qos_requests_memory = "550Mi"
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "1Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  env = {
    "cluster.name": "${local.elasticsearch_cluster_name}"
    "node.roles": "[master]"
    ES_JAVA_OPTS: "-Xms512m -Xmx512m"
    "path.data": "/es-data/data/"
    "path.logs": "/es-data/log/"
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
    # https://www.elastic.co/guide/en/elasticsearch/reference/8.4/security-settings.html#general-security-settings
    # In Elasticsearch 8.0 and later, security is enabled automatically when you start Elasticsearch for the first time.
    # "xpack.security.enabled": false
    # "xpack.security.http.ssl.enabled": false
    # "xpack.security.transport.ssl.enabled": false
    "xpack.security.enabled": false
    "xpack.security.enrollment.enabled": false
    "xpack.security.http.ssl.enabled": false
    "xpack.security.transport.ssl.enabled": false
    "xpack.security.autoconfiguration.enabled": false
    "xpack.license.self_generated.type": "trial"
    # deprecated "xpack.monitoring.collection.enabled": true
  }
  transport_service_port = 9300
  transport_service_target_port = 9300
  service_name_headless = "${local.svc_elasticsearch_headless}"
  service_name = local.svc_elasticsearch_master
}

module "mem-elasticsearch-data" {
  count = var.k8s_manifest_crd ? 0 : 1
  depends_on = [
    module.mem-elasticsearch-master
  ]
  source = "./modules/elk/elasticsearch/es-data"
  app_name = var.app_name
  image_tag = "docker.elastic.co/elasticsearch/elasticsearch:8.4.1"
  imagePullPolicy = "IfNotPresent"
  publish_not_ready_addresses = true
  namespace = local.namespace
  replicas = 2
  qos_limits_cpu = "4000m"
  qos_requests_cpu = "0.750m"
  qos_limits_memory = "10Gi"
  qos_requests_memory = "5Gi"
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "50Gi"
  pvc_storage_class_name = "ibmc-block-silver"
  env = {
    "cluster.name": "${local.elasticsearch_cluster_name}"
    "node.roles": "[data]"
    ES_JAVA_OPTS: "-Xms3g -Xmx3g"
    "path.data": "/es-data/data/"
    "path.logs": "/es-data/log/"
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
    # "xpack.security.enabled": false
    # "xpack.security.http.ssl.enabled": false
    # "xpack.security.transport.ssl.enabled": false
    "xpack.security.enabled": false
    "xpack.security.enrollment.enabled": false
    "xpack.security.http.ssl.enabled": false
    "xpack.security.transport.ssl.enabled": false
    "xpack.security.autoconfiguration.enabled": false
    "xpack.license.self_generated.type": "trial"
    # "xpack.monitoring.collection.enabled": true
  }
  transport_service_port = 9300
  transport_service_target_port = 9300
  service_name_headless = "${local.svc_elasticsearch_headless}"
  service_name = local.svc_elasticsearch_data
}

module "mem-elasticsearch-client" {
  count = var.k8s_manifest_crd ? 0 : 1
  depends_on = [
    module.mem-elasticsearch-data
  ]
  source = "./modules/elk/elasticsearch/es-client"
  app_name = var.app_name
  image_tag = "docker.elastic.co/elasticsearch/elasticsearch:8.4.1"
  imagePullPolicy = "IfNotPresent"
  namespace = local.namespace
  replicas = 2
  qos_limits_cpu = "1000m"
  qos_requests_cpu = "200m"
  qos_limits_memory = "4Gi"
  qos_requests_memory = "3Gi"
  env = {
    "cluster.name": "${local.elasticsearch_cluster_name}"
    "node.roles": "[]"  # A coordinating node.
    ES_JAVA_OPTS: "-Xms2g -Xmx2g"
    HTTP_ENABLE: true
    # ES_PATH_CONF: "/usr/share/elasticsearch/config"
    "discovery.seed_hosts": <<EOL
      "${local.svc_elasticsearch_master}-0.${local.svc_elasticsearch_headless}.${local.namespace}.svc.cluster.local,
       ${local.svc_elasticsearch_master}-1.${local.svc_elasticsearch_headless}.${local.namespace}.svc.cluster.local,
       ${local.svc_elasticsearch_master}-2.${local.svc_elasticsearch_headless}.${local.namespace}.svc.cluster.local"
    EOL
    # "xpack.security.enabled": false
    # "xpack.security.http.ssl.enabled": false
    # "xpack.security.transport.ssl.enabled": false
    "xpack.security.enabled": false
    "xpack.security.enrollment.enabled": false
    "xpack.security.http.ssl.enabled": false
    "xpack.security.transport.ssl.enabled": false
    "xpack.security.autoconfiguration.enabled": false
    "xpack.license.self_generated.type": "trial"
  }
  http_service_port = 9200
  http_service_target_port = 9200
  service_name = local.svc_elasticsearch_client
}

# To check the state of the deployment, use the 'port-forward' command.
#
# $ kubectl port-forward <pod-name-or-svc-headless> 5601:5601 -n memories
# For the service:
# $ kubectl port-forward svc/mem-kibana 5601:5601 -n memories
#
# From a terminal:
# $ curl http://localhost:5601
#
# From a web browser:
# http://localhost:5601
module "mem-kibana" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/elk/kibana"
  app_name = var.app_name
  image_tag = "docker.elastic.co/kibana/kibana:8.4.1"
  imagePullPolicy = "IfNotPresent"
  namespace = local.namespace
  replicas = 1
  qos_limits_cpu = "750m"
  qos_requests_cpu = "200m"
  qos_limits_memory = "1Gi"
  qos_requests_memory = "500Mi"
  env = {
    # https://www.elastic.co/guide/en/kibana/current/settings.html
    # https://github.com/elastic/kibana/blob/main/config/kibana.yml
    "cluster.name": "${local.elasticsearch_cluster_name}"
    "node.roles": "*"
    SVC_DNS_KIBANA: "${local.svc_dns_kibana}"
    # Use 0.0.0.0 to make Kibana listen on all IPs (public and private).wwwwwwwwwwwwwwwwwwwwwwwww
    "server.host": "0.0.0.0"
    "server.port": 5601

    # "http.host": ["_local_", "_site_"]
    "server.publicBaseUrl": "http://169.44.156.170:5601/"

    "elasticsearch.url": "http://${local.svc_elasticsearch_client}.${local.namespace}.svc.cluster.local:9200"
    # https://www.elastic.co/guide/en/kibana/current/settings.html
    # The URLs of the Elasticsearch instances to use for all your queries.
    "elasticsearch.hosts": <<EOL
      "[http://${local.svc_elasticsearch_data}-0.${local.namespace}:9200,
        http://${local.svc_elasticsearch_data}-1.${local.namespace}:9200]"
    EOL
    "elasticsearch.username": "kibana"
    "elasticsearch.password": "kibana"
    # "server.basePath": "/api/v1/proxy/namespaces/kibana/services/kibana-logging"
    # "elasticsearch.ssl.verificationMode": "none"
    "elasticsearch.ssl.verify": false

    "status.allowAnonymous": true

    "xpack.security.enabled": false
    "xpack.security.enrollment.enabled": false
    "xpack.security.http.ssl.enabled": false
    "xpack.security.transport.ssl.enabled": false
    "xpack.security.autoconfiguration.enabled": false
    "xpack.license.self_generated.type": "trial"
    # "server.ssl.enabled": false
    # XPACK_SECURITY_ENABLED: false
    # This deprecated setting has no effect.
    # "xpack.monitoring.enabled": false
    # If set to false, the machine learning APIs are disabled on the node.
    # "xpack.ml.enabled": false
    # "xpack.graph.enabled": false
  }
  service_port = 5601
  service_target_port = 5601
  service_name = local.svc_kibana
}

/**
module "mem-logstash" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/elk/logstash"
  app_name = var.app_name
  image_tag = "docker.elastic.co/logstash/logstash:7.5.0"
  imagePullPolicy = "IfNotPresent"
  namespace = local.namespace
  replicas = 1
  service_port = 5044
  service_target_port = 5044
  service_name = "mem-logstash"
}
**/
# ***/  # elk
/***
# Filebeat is the agent that ships logs to Logstash.
module "mem-filebeat" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/ELK/filebeat"
  path_to_files = "./utility-files/ELK/filebeat"
  app_name = var.app_name
  image_tag = "docker.elastic.co/beats/filebeat:7.5.0"
  imagePullPolicy = "IfNotPresent"
  namespace = local.namespace
  host_network = true
  # Limits and requests for CPU resources are measured in millicores. If the container needs one
  # full core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the
  # value of '250m.'
  qos_limits_cpu = "600m"
  qos_requests_cpu = "500m"
  qos_limits_memory = "200Mi"
  qos_requests_memory = "100Mi"
  service_name = "mem-filebeat"
}
***/

###################################################################################################
# mongodb                                                                                         #
###################################################################################################
/*** mongodb - deployment
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
***/  # mongodb - deployment

/*** mongodb - statefulset
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
  imagePullPolicy = "IfNotPresent"
  # image_tag = "rabbitmq:3.9.7-alpine"
  path_rabbitmq_files = "./utility-files/rabbitmq"
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

/*** rabbitmq - statefulset
# StatefulSet.
module "mem-rabbitmq" {
  count = var.k8s_manifest_crd ? 0 : 1
  source = "./modules/rabbitmq-statefulset"
  app_name = var.app_name
  app_version = var.app_version
  # This image has the RabbitMQ dashboard.
  image_tag = "rabbitmq:3.9.7-management-alpine"
  imagePullPolicy = "IfNotPresent"
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
***/  # rabbitmq - statefulset

###################################################################################################
# Application                                                                                     #
###################################################################################################
/*** app
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
    SVC_DNS_METADATA: local.svc_dns_metadata
    SVC_DNS_HISTORY: local.svc_dns_history
    SVC_DNS_VIDEO_UPLOAD: local.svc_dns_video_upload
    SVC_DNS_VIDEO_STREAMING: local.svc_dns_video_streaming
    SVC_DNS_KIBANA: local.svc_dns_kibana
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
  # service_session_affinity = "None"
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
  service_name = local.svc_history
}

module "mem-metadata" {
  count = var.k8s_manifest_crd ? 0 : 1
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
  service_name = local.svc_video_upload
}
***/  # app
