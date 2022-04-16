
# The hosts file is used to map domain names (hostnames) to IP addresses. It is a plain-text file used by all operating systems including, Linux, Windows, and macOS.
# The hosts file has priority over DNS. When you type in the domain name of a web site you want to visit, the domain name must be translated into its corresponding IP Address. The operating system first checks its hosts file for the corresponding domain, and if there is no entry for the domain, it will query the configured DNS servers to resolve the specified domain name. This affects only the computer on which the change is made, rather than how the domain is resolved worldwide.
# Entries in the hosts file have the following format:
#    IPAddress DomainName [DomainAliases]
# The IP address and the domain names should be separated by at least one space or tab. The lines starting with # are comments and are ignored.

# On Linux, the full path to the file is /etc/hosts.
# On Windows, the full path to the file is C:\Windows\System32\drivers\etc\hosts.

module "traefik" {
  source = "./modules/traefik"
  app_name = var.app_name
  namespace = local.namespace
  service_name = "mem-traefik"
}

module "middleware" {
  source = "./modules/traefik/middlewares"
  app_name = var.app_name
  namespace = local.namespace
  traefik_username = var.traefik_username
  traefik_password = var.traefik_password
  service_name = "mem-middleware"
}
