resource "helm_release" "this" {
  for_each = {
    for package_key in keys(var.helm.packages) : package_key => package_key
    if lookup(var.helm.packages[package_key], "enabled", true)
  }

  name             = coalesce(lookup(var.helm.packages[each.key], "name", null), each.key)
  repository       = var.helm.packages[each.key].repository
  chart            = var.helm.packages[each.key].chart
  version          = lookup(var.helm.packages[each.key], "version", null)
  namespace        = lookup(var.helm.packages[each.key], "namespace", "default")
  create_namespace = true
  upgrade_install  = lookup(var.helm.packages[each.key], "upgrade_install", false)

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  values = concat(
    [yamlencode(lookup(var.helm.packages[each.key], "values", {}))],
    [
      for values_file in lookup(var.helm.packages[each.key], "values_files", []) :
      templatefile("${path.module}/${values_file}", {
        togglemaster_dashboard = jsonencode(file("${path.module}/dashboards/togglemaster.json"))
      })
    ]
  )
}

output "release_statuses" {
  value = { for key, release in helm_release.this : key => release.status }
}
