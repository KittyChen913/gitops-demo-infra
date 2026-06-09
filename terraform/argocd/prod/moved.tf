moved {
  from = kubernetes_namespace_v1.argocd
  to   = module.argocd.kubernetes_namespace_v1.argocd
}

moved {
  from = kustomization_resource.argocd_p0
  to   = module.argocd.kustomization_resource.argocd_p0
}

moved {
  from = kustomization_resource.argocd_p1
  to   = module.argocd.kustomization_resource.argocd_p1
}

moved {
  from = kustomization_resource.argocd_p2
  to   = module.argocd.kustomization_resource.argocd_p2
}

moved {
  from = kubernetes_secret_v1.argocd_worker_cluster
  to   = module.argocd.kubernetes_secret_v1.argocd_worker_cluster
}

moved {
  from = local_sensitive_file.mgmt_kubeconfig
  to   = module.argocd.local_sensitive_file.mgmt_kubeconfig
}

moved {
  from = null_resource.argocd_self_app
  to   = module.argocd.null_resource.argocd_self_app
}

moved {
  from = null_resource.argocd_root_app
  to   = module.argocd.null_resource.argocd_root_app
}
