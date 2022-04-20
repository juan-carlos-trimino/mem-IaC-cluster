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
variable "middleware_rabbitmq" {
  type = string
}
variable "svc_rabbitmq" {
  type = string
}
variable "service_name" {
  type = string
}

resource "kubernetes_manifest" "ingress-route" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind = "IngressRoute"
    metadata = {
      name = "${var.service_name}"
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
          match = "Host(`trimino.com`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))"
          priority = 10
          middlewares = [
            {
              name = var.middleware_dashboard
              namespace = var.namespace
            }
          ]
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
          match = "Host(`trimino.com`) && (PathPrefix(`/`) || PathPrefix(`/history`) || PathPrefix(`/upload`))"
          priority = 10
          middlewares = [
            {
              name = var.middleware_gateway
              namespace = var.namespace
            }
          ]
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
          match = "Host(`trimino.com`) && PathPrefix(`/rabbitmq`)"
          priority = 10
          middlewares = [
            {
              name = var.middleware_rabbitmq
              namespace = var.namespace
            }
          ]
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
    }
  }
}
