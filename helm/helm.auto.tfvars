helm = {
  packages = {
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
