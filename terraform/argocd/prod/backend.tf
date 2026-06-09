terraform {
  backend "s3" {
    bucket       = "gitops-demo-tfstate"
    region       = "ap-southeast-1"
    key          = "gitops-demo-infra/prod/argocd/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
