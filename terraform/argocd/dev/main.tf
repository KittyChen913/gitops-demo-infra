module "argocd" {
  source = "../../modules/argocd"

  aws_region           = "ap-southeast-1"
  ssm_path_prefix      = "/gitops/dev/clusters"
  mgmt_cluster_label   = "lke-dev-mgmt"
  worker_cluster_label = "lke-dev-ateam"
  argocd_namespace     = "argocd"
  root_app_teams = {
    ateam = "ateam/root-application-dev.yaml"
  }
}
