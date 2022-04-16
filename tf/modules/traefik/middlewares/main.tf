/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable "app_name" {
  type = string
}
variable "namespace" {
  type = string
}
variable "service_name" {
  type = string
}
variable "traefik_username" {
  type = string
}
variable "traefik_password" {
  type = string
}

resource "kubernetes_secret" "secret" {
  metadata {
    name = "${var.service_name}-dashboard-secret"
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  # Plain-text data.
  data = {
    # The second argument is optional and will default to 10 if unspecified. Since a bcrypt hash
    # value includes a randomly selected salt, each call to this function will return a different
    # value, even if the given string and cost are the same.
    # Traefik supports passwords hashed with MD5, SHA1, or BCrypt.
    #
    # From the command line:
    # Using the htpasswd utility, encrypt a username and password for Traefik to use. First, let's
    # install (ubuntu) the utility, which is part of the apache2-utils package to manage usernames
    # and passwords with access to restricted content.
    # $ sudo apt update
    # $ sudo apt install apache2-utils
    # Now, let's encrypt the credentials for a username and password. The output of the utility
    # will be piped to openssl for base64 encoding.
    # $ htpasswd -nbB <username> <password> | openssl base64
    # To verify the output from htpasswd:
    # $ echo "Output from htpasswd" | base64 -d
    users = "${var.traefik_username}:${bcrypt(var.traefik_password, 10)}"
  }
  type = "Opaque"
}

resource "kubernetes_manifest" "middleware-dashboard" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind = "Middleware"
    metadata = {
      name = "${var.service_name}-dashboard"
      namespace = var.namespace
      labels = {
        app = var.app_name
      }
    }
    #
    spec = {
      basicAuth = {
        removeHeader = true
        # The users option is an array of authorized users. Each user will be declared using the
        # name:encoded-password format.
        secret = kubernetes_secret.secret.metadata[0].name
      }
    }
  }
}


