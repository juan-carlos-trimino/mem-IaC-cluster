####################
# GLOBAL VARIABLES #
####################
variable app_name {
  type = string
  description = "The name of the application."
  default = "memories"
}

variable app_version {
  type = string
  description = "The application version."
  default = "1.0.0"
}

# The limitations of the kubernetes_manifest resource
# ---------------------------------------------------
# If you want to create arbitrary Kubernetes resources in a cluster using Terraform, particularly
# CRDs (Custom Resource Definitions), you can use the kubernetes_manifest resource from the
# Kubernetes provider, but with these limitations:
# (1) This resource requires API access during the planning time. This means the cluster has to be
#     accessible at plan time and thus cannot be created in the same apply operation. That is, it
#     is required to use two (2) separate Terraform apply steps: (1) Provision the cluster;
#     (2) Create the resource.
# (2) Any CRD (Custom Resource Definition) must already exist in the cluster during the planning
#     phase. That is, it is required to use two (2) separate Terraform apply steps: (1) Install the
#     CRDs; (2) Install the resources that are using the CRDs.
# This are Terraform limitations, not specific to Kubernetes.
variable k8s_manifest_crd {
  type = bool
  default = "true"
}
