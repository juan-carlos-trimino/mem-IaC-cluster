module "traefik" {
  source = "./modules/traefik"
  namespace = local.namespace
}
