resource "helm_release" "this" {
  for_each = {
    for package_key, package in var.helm.packages : package_key => package
    if package.enabled
  }

  name             = coalesce(each.value.name, each.key)
  repository       = each.value.repository
  chart            = each.value.chart
  version          = each.value.version
  namespace        = each.value.namespace
  create_namespace = true
  upgrade_install  = each.value.upgrade_install

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  values = [yamlencode(each.value.values)]
}

output "release_statuses" {
  value = { for key, release in helm_release.this : key => release.status }
}
