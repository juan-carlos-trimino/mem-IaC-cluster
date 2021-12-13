##################################################
# https://registry.terraform.io/browse/providers #
##################################################

#The ~> operator is a convenient shorthand for allowing only patch releases within a specific minor release.

terraform {
  # Terraform version.
  required_version = ">= 1.0.0"
  required_providers {
    ibm = {
      source = "ibm-cloud/ibm"
      version = ">= 1.30.2"
    }

    kubernetes = {
      source = "hashicorp/kubernetes"
      version = ">= 2.4.1"
    }

    null = {
      source = "hashicorp/null"
      version = ">= 3.1.0"
    }
  }
}

####################################################################################
# Configure the IBM Provider                                                       #
# https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs#resource_group #
# https://cloud.ibm.com/iam/overview                                               #
####################################################################################
provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region = var.region
  ibmcloud_timeout = var.ibmcloud_timeout
}

###########################################################################################################
# https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/container_cluster_config #
###########################################################################################################
provider "kubernetes" {
  host = data.ibm_container_cluster_config.cluster_config.host
  token = data.ibm_container_cluster_config.cluster_config.token
  cluster_ca_certificate = data.ibm_container_cluster_config.cluster_config.ca_certificate
}

provider "null" {
}
