
module "cert-manager" {
  depends_on = [kubernetes_namespace.ns]
  source = "./modules/cert-manager/cert-manager"
  namespace = local.namespace
}

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
