/***
-------------------------------------------------------
A Terraform reusable module for deploying microservices
-------------------------------------------------------
Define input variables to the module.
***/
variable app_name {
  type = string
}
variable namespace {
  type = string
}
variable svc_gateway {
  type = string
}
variable middleware_gateway_basic_auth {
  type = string
}
variable middleware_dashboard_basic_auth {
  type = string
}
variable middleware_redirect_https {
  type = string
}
variable middleware_security_headers {
  type = string
}
variable tls_store {
  type = string
}
variable tls_options {
  type = string
}
variable secret_name {
  type = string
}
variable issuer_name {
  type = string
}
variable host_name {
  type = string
}
variable service_name {
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
      # If not specified, HTTP routers will accept requests from all defined entry points. If you
      # want to limit the router scope to a set of entry points, set the entryPoints option.
      # Traefik handles requests using the web (HTTP) and websecure (HTTPS) entrypoints.
      entryPoints = [  # Listening ports.
        "web",
        "websecure"
      ]
      routes = [
        {
          kind = "Rule"
          match = "Host(`${var.host_name}`, `www.${var.host_name}`) && (Path(`/upload`) || Path(`/api/upload`))"
          priority = 50
          middlewares = [
            {
              name = var.middleware_redirect_https
              namespace = var.namespace
            },
            {
              name = var.middleware_security_headers
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
          match = "Host(`${var.host_name}`, `www.${var.host_name}`) && (Path(`/video`) || Path(`/api/video`))"
          priority = 50
          middlewares = [
            {
              name = var.middleware_redirect_https
              namespace = var.namespace
            },
            {
              name = var.middleware_security_headers
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
          match = "Host(`${var.host_name}`, `www.${var.host_name}`) && Path(`/history`)"
          priority = 50
          middlewares = [
            {
              name = var.middleware_redirect_https
              namespace = var.namespace
            },
            {
              name = var.middleware_security_headers
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
          match = "Host(`${var.host_name}`, `www.${var.host_name}`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))"
          priority = 40
          middlewares = [
            {
              name = var.middleware_dashboard_basic_auth
              namespace = var.namespace
            },
            {
              name = var.middleware_redirect_https
              namespace = var.namespace
            },
            {
              name = var.middleware_security_headers
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
          # For testing, use one of the free wildcard DNS services for IP addresses (xip.io,
          # nip.io (https://nip.io/), sslip.io (https://sslip.io/), ip6.name, and hipio). By using
          # one of these services, the /etc/hosts file does not need to be changed.
          # match = "Host(`169.46.98.220.nip.io`) && PathPrefix(`/`)"
          # match = "Host(`memories.mooo.com`) && (PathPrefix(`/`) || Path(`/upload`) || Path(`/api/upload`))"
          match = "Host(`${var.host_name}`, `www.${var.host_name}`) && PathPrefix(`/`)"
          priority = 20
          # The rule is evaluated 'before' any middleware has the opportunity to work, and 'before'
          # the request is forwarded to the service.
          # Middlewares are applied in the same order as their declaration in router.
          middlewares = [
            {
              name = var.middleware_gateway_basic_auth
              namespace = var.namespace
            },
            {
              name = var.middleware_redirect_https
              namespace = var.namespace
            },
            # See tls below.
            # Add this Middleware to the IngressRoute, then generate a new report from SSLLabs. The
            # configuration now reflects the highest standards in TLS security (A+).
            {
              name = var.middleware_security_headers
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
        }
      ]
      # When a TLS section is specified, it instructs Traefik that the current router is dedicated
      # to HTTPS requests only (and that the router should ignore HTTP (non TLS) requests). Traefik
      # will terminate the SSL connections (meaning that it will send decrypted data to the
      # services).
      #
      # To perform an analysis of the TLS handshake using SSLLabs, go to
      # https://www.ssllabs.com/ssltest/.
      tls = {
        # Although you can configure Traefik Proxy to use multiple certificatesresolvers,  an
        # IngressRoute is only ever associated with a single one. That association happens with the
        # tls.certResolver key.
        certResolver = "le"
        # Subject Alternative Name (SAN) is an extension to the X.509 specification that allows you
        # to secure multiple domains with a single SSL/TLS certificate. You may include any
        # combination of domain names, subdomains, IP addresses, and local host names up to a
        # maximum of 250 (vendor specific).
        #
        # SAN is a very useful tool to fix the "www" versus the root domain ("no-www") problem. If
        # you are issued an SSL/TLS certificate for "www.trimino.xyz", it will only work for
        # "www.trimino.xyz", but not for the root domain "trimino.xyz". By adding a SAN value of
        # "trimino.xyz" to the certificate fixes this problem. The converse of this works as well;
        # i.e., you can add a SAN value of "www.trimino.xyz" for a certificate issued just for the
        # root domain "trimino.xyz".
        domains = [
          {
            main = var.host_name
            sans = [  # URI Subject Alternative Names
              "www.${var.host_name}"
            ]
          }
        ]
        # Use the secret created by cert-manager to terminate the TLS connection.
        # cert-manager will store the created certificate in this secret.
        # secretName = var.secret_name
        store = {
          name = var.tls_store
        }
        # Traefik provides several TLS options
        # (https://doc.traefik.io/traefik/https/tls/#tls-options) to configure some parameters of
        # the TLS connection.
        #
        # Before enabling these options, perform an analysis of the TLS connection by using SSLLabs
        # (https://www.ssllabs.com/ssltest/). The SSLLabs service provides a detailed report of
        # various aspects of TLS with a color-coded report.
        #
        # Then after enabling these options, repeat the analysis and compare the new report with
        # previous report.
        options = {
          name = var.tls_options
          namespace = var.namespace
        }
      }
    }
  }
}
