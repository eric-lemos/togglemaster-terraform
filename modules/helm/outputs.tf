output "release_statuses" {
  value = { for key, release in helm_release.this : key => release.status }
}
