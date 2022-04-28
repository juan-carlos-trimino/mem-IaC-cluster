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
variable "middleware_dashboard" {
  type = string
}
variable "middleware_gateway" {
  type = string
}
variable "svc_gateway" {
  type = string
}
variable "middleware_rabbitmq1" {
  type = string
}
variable "middleware_rabbitmq2" {
  type = string
}
variable "svc_rabbitmq" {
  type = string
}
# variable "secret_name" {
#   type = string
# }
variable "service_name" {
  type = string
}

resource "kubernetes_manifest" "ingress-route" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    # This CRD is Traefik-specific.
    kind = "IngressRoute"
    metadata = {
      name = var.service_name
      namespace = var.namespace
      labels = {
        app = var.app_name
      }
    }
    #
    spec = {
      entryPoints = [  # Listening ports.
        "web",
        "websecure"
      ]
      routes = [
        {
          kind = "Rule"
          # match = "Host(`trimino.com`)"
          # match = "Host(`trimino.com`) && (PathPrefix(`/`) || PathPrefix(`/upload`))"
          match = "Host(`trimino.com`) && (PathPrefix(`/`) || PathPrefix(`/video`) || PathPrefix(`/upload`) || PathPrefix(`/history`) || PathPrefix(`/api/video`) || PathPrefix(`/api/upload`))"
          priority = 1
          # middlewares = [
          #   {
          #     name = var.middleware_gateway
          #     namespace = var.namespace
          #   }
          # ]
          services = [
            {
              kind = "Service"
              name = var.svc_gateway
              namespace = var.namespace
              port = 80  # K8s service.
              weight = 1
              passHostHeader = true
              responseForwarding = {
                flushInterval = "100ms"
              }
              strategy = "RoundRobin"
            }
          ]
        },
        {
          kind = "Rule"
          match = "Host(`trimino.com`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))"
          priority = 10
          # middlewares = [
          #   {
          #     name = var.middleware_dashboard
          #     namespace = var.namespace
          #   }
          # ]
          services = [
            {
              kind = "TraefikService"
              # If you enable the API, a new special service named api@internal is created and can
              # then be referenced in a router.
              name = "api@internal"
              port = 9000  # K8s service.
              # (default 1) A weight used by the weighted round-robin strategy (WRR).
              weight = 1
              # (default true) PassHostHeader controls whether to leave the request's Host Header
              # as it was before it reached the proxy, or whether to let the proxy set it to the
              # destination (backend) host.
              passHostHeader = true
              responseForwarding = {
                # (default 100ms) Interval between flushes of the buffered response body to the
                # client.
                flushInterval = "100ms"
              }
              strategy = "RoundRobin"
            }
          ]
        },
        {
          kind = "Rule"
          match = "Host(`trimino.com`) && PathPrefix(`/rabbitmq`)"
          priority = 11
          # middlewares = [
          #   {
          #     name = var.middleware_rabbitmq1
          #     namespace = var.namespace
          #   }
          #   # {
          #   #   name = var.middleware_rabbitmq2
          #   #   namespace = var.namespace
          #   # }
          # ]
          services = [
            {
              kind = "Service"
              name = var.svc_rabbitmq
              namespace = var.namespace
              port = 15672  # K8s service.
              weight = 1
              passHostHeader = true
              responseForwarding = {
                flushInterval = "100ms"
              }
              strategy = "RoundRobin"
            }
          ]
        }
      ]
      # To perform an analysis of the TLS handshake using SSLLabs, go to
      # https://www.ssllabs.com/ssltest/.
      tls = {
        # Use the secret created by cert-manager to terminate the TLS connection.
        # secretName = var.secret_name
        store = {
          name = "default"
        }
      }
    }
  }
}
