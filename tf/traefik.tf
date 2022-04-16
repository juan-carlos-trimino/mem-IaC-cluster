
# The hosts file is used to map domain names (hostnames) to IP addresses. It is a plain-text file used by all operating systems including, Linux, Windows, and macOS.
# The hosts file has priority over DNS. When you type in the domain name of a web site you want to visit, the domain name must be translated into its corresponding IP Address. The operating system first checks its hosts file for the corresponding domain, and if there is no entry for the domain, it will query the configured DNS servers to resolve the specified domain name. This affects only the computer on which the change is made, rather than how the domain is resolved worldwide.
# Entries in the hosts file have the following format:
#    IPAddress DomainName [DomainAliases]
# The IP address and the domain names should be separated by at least one space or tab. The lines starting with # are comments and are ignored.

# On Linux, the full path to the file is /etc/hosts.
# On Windows, the full path to the file is C:\Windows\System32\drivers\etc\hosts.
locals {
  middleware_dashboard = "mem-middleware-dashboard"
}

module "traefik" {
  source = "./modules/traefik/traefik"
  app_name = var.app_name
  namespace = local.namespace
  service_name = "mem-traefik"
}

module "middleware-dashboard" {
  source = "./modules/traefik/middlewares"
  app_name = var.app_name
  namespace = local.namespace
  # While the dashboard in itself is read-only, it is good practice to secure access to it.
  traefik_dashboard_username = var.traefik_dashboard_username
  traefik_dashboard_password = var.traefik_dashboard_password
  service_name = local.middleware_dashboard
}

module "ingress-route" {
  source = "./modules/traefik/ingress-route"
  app_name = var.app_name
  namespace = local.namespace
  middleware_dashboard = local.middleware_dashboard
  service_name = "mem-ingress-route"
}





/***
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
***/
