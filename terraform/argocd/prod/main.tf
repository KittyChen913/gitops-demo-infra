module "argocd" {
  source = "../../modules/argocd"

  aws_region           = "ap-southeast-1"
  ssm_path_prefix      = "/gitops/prod/clusters"
  mgmt_cluster_label   = "lke-prod-mgmt"
  worker_cluster_label = "lke-prod-ateam"
  argocd_namespace     = "argocd"
  root_app_teams = {
    ateam = "ateam/root-application-prod.yaml"
  }
}
