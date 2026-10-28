terraform {
  backend "s3" {
    key          = "helm/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
