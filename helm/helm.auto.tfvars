helm = {
  packages = {
    monitoring = {
      repository   = "https://prometheus-community.github.io/helm-charts"
      chart        = "kube-prometheus-stack"
      version      = "92.17.0"
      namespace    = "observability"
      values_files = ["values/monitoring.yaml"]
    }

    loki = {
      repository   = "https://grafana.github.io/helm-charts"
      chart        = "loki"
      version      = "7.5.0"
      namespace    = "observability"
      values_files = ["values/loki.yaml"]
    }

    otel-agent = {
      repository   = "https://open-telemetry.github.io/opentelemetry-helm-charts"
      chart        = "opentelemetry-collector"
      version      = "0.178.2"
      namespace    = "observability"
      values_files = ["values/otel-agent.yaml"]
    }

    otel-gateway = {
      repository   = "https://open-telemetry.github.io/opentelemetry-helm-charts"
      chart        = "opentelemetry-collector"
      version      = "0.178.2"
      namespace    = "observability"
      values_files = ["values/otel-gateway.yaml"]
    }

    ingress-nginx = {
      upgrade_install = true
      repository      = "https://kubernetes.github.io/ingress-nginx"
      chart           = "ingress-nginx"
      version         = "4.15.1"
      namespace       = "ingress-nginx"
      values = {
        controller = {
          ingressClass             = "nginx"
          watchIngressWithoutClass = false
          ingressClassResource = {
            enabled = true
            name    = "nginx"
          }
          service = {
            type = "LoadBalancer"
          }
        }
      }
    }

    metrics-server = {
      upgrade_install = true
      repository      = "https://kubernetes-sigs.github.io/metrics-server/"
      chart           = "metrics-server"
      version         = "3.14.0"
      namespace       = "kube-system"
      values = {
        args = ["--kubelet-insecure-tls"]
      }
    }

    argocd = {
      upgrade_install = true
      repository      = "https://argoproj.github.io/argo-helm"
      chart           = "argo-cd"
      version         = "10.6.0"
      namespace       = "argocd"
      values = {
        server = {
          service = {
            type = "LoadBalancer"
          }
        }
      }
    }
  }
}
