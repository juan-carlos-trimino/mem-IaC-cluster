# To connect to a specific pod without going through a service, use the 'port-forward' command.
#
# $ kubectl port-forward <pod-name> <local-port>:<pod-port> -n <namespace>
#
# Once the port forwarder is running, from a different terminal (or web browser) connect to the pod
# through the local port.
#
# From a terminal:
# $ curl http://localhost:<local-port>
#
# From a web browser:
# http://localhost:<local-port>





# If you notice, we used the same minor and major version numbers when deploying the ELK stack components, so that all of them could be versioned 6.8.4. This is intentional as the ELK stack components will work with each other as long you follow the compatibility matrix. You are strongly encouraged to review the Elastic Support Matrix document before attempting to deploy the ELK stack in your environment.
# https://www.elastic.co/support/matrix
# ELK stack works by receiving log data from different sources. For the source to send its logs, it needs an agent. There are many agents that can do this role like Logstash, Fluentd, and Filebeat.


/****

# To check the state of the deployment, use the 'port-forward' command.
#
# $ kubectl port-forward <pod-name-or-svc-name> 9200:9200 -n memories
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
module "mem-elasticsearch" {
  source = "./modules/ELK-statefulset/elasticsearch"
  app_name = var.app_name
  app_version = var.app_version
  image_tag = "docker.elastic.co/elasticsearch/elasticsearch:7.5.0"
  imagePullPolicy = "IfNotPresent"
  publish_not_ready_addresses = true
  namespace = local.namespace
  replicas = 3
  # Limits and request for CPU resources are measured in millicores. If the container needs one full
  # core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the value of
  # '250m.'
  # Burstable class because there is a need for more CPU upon initialization.
  qos_limits_cpu = "1000m"
  qos_requests_cpu = "100m"
  # By default, Elasticsearch allocates 2GB of system memory for the database.
  qos_limits_memory = "3Gi"
  qos_requests_memory = "2Gi"
  pvc_access_modes = ["ReadWriteOnce"]
  pvc_storage_size = "50Gi"
  pvc_storage_class_name = "ibmc-block-silver"

  env = {
    # Elasticsearch recommends that the value for the maximum and minimum heap size be identical.
    ES_JAVA_OPTS: "-Xms2g -Xmx2g"
    # A node can only join a cluster when it shares its cluster.name with all the other nodes in
    # the cluster. The default name is elasticsearch, but you should change it to an appropriate
    # name which describes the purpose of the cluster.
    "cluster.name": "elk-logs"
    # It is vitally important to the health of your node that none of the JVM is ever swapped out
    # to disk.
    ##### "bootstrap.memory_lock": true  # Swapping is disabled.
    # When you start an Elasticsearch cluster for the first time, a cluster bootstrapping step
    # determines the set of master-eligible nodes whose votes are counted in the first election.
    # In development mode, with no discovery settings configured, this step is performed
    # automatically by the nodes themselves.
    #
    # Because auto-bootstrapping is inherently unsafe, when starting a new cluster in production
    # mode, you must explicitly list the master-eligible nodes whose votes should be counted in
    # the very first election.
    "cluster.initial_master_nodes": "mem-elasticsearch-0, mem-elasticsearch-1, mem-elasticsearch-2"
  }
  rest_api_service_port = 9200
  rest_api_service_target_port = 9200
  inter_node_service_port = 9300
  inter_node_service_target_port = 9300
  service_name = "mem-elasticsearch"
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
  source = "./modules/ELK-statefulset/kibana"
  app_name = var.app_name
  app_version = var.app_version
  image_tag = "docker.elastic.co/kibana/kibana:7.5.0"
  imagePullPolicy = "IfNotPresent"
  publish_not_ready_addresses = true
  namespace = local.namespace
  # replicas = 3
  # Limits and request for CPU resources are measured in millicores. If the container needs one full
  # core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the value of
  # '250m.'
  # Burstable class because there is a need for more CPU upon initialization.
  qos_limits_cpu = "2000m"
  qos_requests_cpu = "500m"
  # # By default, Elasticsearch allocates 2GB of system memory for the database.
  qos_limits_memory = "2.5Gi"
  qos_requests_memory = "1Gi"
  # pvc_access_modes = ["ReadWriteOnce"]
  # pvc_storage_size = "25Gi"
  # pvc_storage_class_name = "ibmc-block-silver"
  env = {
    ELASTICSEARCH_HOSTS: local.svc_dns_elasticsearch
  }
  service_port = 5601
  service_target_port = 5601
  service_name = "mem-kibana"
}

module "mem-logstash" {
  source = "./modules/ELK-statefulset/logstash"
  app_name = var.app_name
  app_version = var.app_version
  image_tag = "docker.elastic.co/logstash/logstash:7.5.0"
  imagePullPolicy = "IfNotPresent"
  publish_not_ready_addresses = true
  namespace = local.namespace
  # replicas = 3
  # Limits and request for CPU resources are measured in millicores. If the container needs one full
  # core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the value of
  # '250m.'
  # Burstable class because there is a need for more CPU upon initialization.
  # qos_limits_cpu = "1000m"
  # qos_requests_cpu = "100m"
  # By default, Elasticsearch allocates 2GB of system memory for the database.
  # qos_limits_memory = "3Gi"
  # qos_requests_memory = "2Gi"
  # pvc_access_modes = ["ReadWriteOnce"]
  # pvc_storage_size = "25Gi"
  # pvc_storage_class_name = "ibmc-block-silver"
  service_port = 5044
  service_target_port = 5044
  service_name = "mem-logstash"
}

module "mem-filebeat" {
  source = "./modules/ELK-statefulset/filebeat"
  app_name = var.app_name
  app_version = var.app_version
  image_tag = "docker.elastic.co/beats/filebeat:7.5.0"
  imagePullPolicy = "IfNotPresent"
  publish_not_ready_addresses = true
  namespace = local.namespace
  # replicas = 3
  # Limits and request for CPU resources are measured in millicores. If the container needs one full
  # core to run, use the value '1000m.' If the container only needs 1/4 of a core, use the value of
  # '250m.'
  # Burstable class because there is a need for more CPU upon initialization.
  # qos_limits_cpu = "1000m"
  # qos_requests_cpu = "100m"
  # By default, Elasticsearch allocates 2GB of system memory for the database.
  # qos_limits_memory = "3Gi"
  # qos_requests_memory = "2Gi"
  # pvc_access_modes = ["ReadWriteOnce"]
  # pvc_storage_size = "25Gi"
  # pvc_storage_class_name = "ibmc-block-silver"
  service_port = 5044
  service_target_port = 5044
  service_name = "mem-filebeat"
}
****/