locals {
  environment_config = jsondecode(file("${path.module}/../environments/dev.json"))
}

module "argocd" {
  source = "../../modules/argocd"

  ssm_path_prefix      = local.environment_config.ssm_path_prefix
  mgmt_cluster_label   = local.environment_config.mgmt_cluster_label
  worker_cluster_label = local.environment_config.worker_cluster_label
  argocd_namespace     = "argocd"
  root_applications    = local.environment_config.root_applications
}
