variable "aws_region" {
  description = "AWS region（SSM Parameter Store 所在區域）"
  type        = string
  default     = "ap-southeast-1"
}

variable "ssm_path_prefix" {
  description = "SSM Parameter Store 路徑前綴，例如 /k8s/clusters"
  type        = string
  default     = "/k8s/clusters"
}

variable "mgmt_cluster_label" {
  description = "Management cluster 標籤，對應 SSM 路徑中的 cluster 名稱（例如 lke-dev-mgmt）"
  type        = string
}

variable "worker_cluster_label" {
  description = "Worker cluster 標籤，對應 SSM 路徑中的 cluster 名稱（例如 lke-dev-ateam）"
  type        = string
}

variable "argocd_namespace" {
  description = "ArgoCD 部署的 Kubernetes namespace"
  type        = string
  default     = "argocd"
}

variable "root_app_teams" {
  description = "各 team 的 Root Application YAML 路徑 map（相對於 argocd/bootstrap/），key 為 team 名稱"
  type        = map(string)
  default     = {}
}


