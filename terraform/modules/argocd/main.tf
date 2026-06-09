# ── SSM Parameter Store：lke-dev-mgmt 連線資訊 ────────────────────────────────
# 路徑格式：${ssm_path_prefix}/${mgmt_cluster_label}/<param>
data "aws_ssm_parameter" "api_endpoint" {
  name = "${var.ssm_path_prefix}/${var.mgmt_cluster_label}/api-endpoint"
}

data "aws_ssm_parameter" "ca_cert" {
  name = "${var.ssm_path_prefix}/${var.mgmt_cluster_label}/ca-cert"
}

# token 為 SecureString，需啟用解密
data "aws_ssm_parameter" "token" {
  name            = "${var.ssm_path_prefix}/${var.mgmt_cluster_label}/token"
  with_decryption = true
}

# ── SSM Parameter Store：worker cluster 連線資訊 ──────────────────────────────
# 路徑格式：${ssm_path_prefix}/${worker_cluster_label}/<param>
data "aws_ssm_parameter" "worker_api_endpoint" {
  name = "${var.ssm_path_prefix}/${var.worker_cluster_label}/api-endpoint"
}

data "aws_ssm_parameter" "worker_ca_cert" {
  name = "${var.ssm_path_prefix}/${var.worker_cluster_label}/ca-cert"
}

data "aws_ssm_parameter" "worker_token" {
  name            = "${var.ssm_path_prefix}/${var.worker_cluster_label}/token"
  with_decryption = true
}

# ── Management Cluster kubeconfig（共用於 kustomization provider 與 local-exec）─
locals {
  manifest_root = abspath("${path.module}/../../../argocd")

  mgmt_kubeconfig_yaml = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = "mgmt"
      cluster = {
        server                       = data.aws_ssm_parameter.api_endpoint.value
        "certificate-authority-data" = data.aws_ssm_parameter.ca_cert.value
      }
    }]
    users = [{
      name = "mgmt"
      user = { token = data.aws_ssm_parameter.token.value }
    }]
    contexts = [{
      name    = "mgmt"
      context = { cluster = "mgmt", user = "mgmt" }
    }]
    "current-context" = "mgmt"
  })
}

# ── ArgoCD Namespace ──────────────────────────────────────────────────────────
# 明確建立 namespace，確保在所有 kustomize 資源前就存在，
# 避免 kbst provider 平行建立時 ConfigMap 找不到 namespace 的競態問題。
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.argocd_namespace
  }
}

# ── ArgoCD 安裝（Kustomize）────────────────────────────────────────────────────
# 透過 kbst/kustomization provider 套用 argocd/install/ 目錄。
# priority group 0：CRDs（最優先）
# priority group 1：ClusterRole、ClusterRoleBinding 等 cluster-scoped 資源
# priority group 2：Deployment、Service 等 namespace-scoped 資源
data "kustomization_build" "argocd_install" {
  path = "${local.manifest_root}/install"
}

resource "kustomization_resource" "argocd_p0" {
  for_each   = data.kustomization_build.argocd_install.ids_prio[0]
  manifest   = data.kustomization_build.argocd_install.manifests[each.value]
  depends_on = [kubernetes_namespace_v1.argocd]
}

resource "kustomization_resource" "argocd_p1" {
  for_each   = data.kustomization_build.argocd_install.ids_prio[1]
  manifest   = data.kustomization_build.argocd_install.manifests[each.value]
  depends_on = [kustomization_resource.argocd_p0]
}

resource "kustomization_resource" "argocd_p2" {
  for_each   = data.kustomization_build.argocd_install.ids_prio[2]
  manifest   = data.kustomization_build.argocd_install.manifests[each.value]
  depends_on = [kustomization_resource.argocd_p1]
}

# ── ArgoCD Cluster Secret（Worker Cluster 註冊）────────────────────────────────
# 在 management cluster 的 argocd namespace 建立 Cluster Secret，
# ArgoCD 透過此 Secret 連線管理 worker cluster。
# 格式參考：https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters
resource "kubernetes_secret_v1" "argocd_worker_cluster" {
  metadata {
    name      = "cluster-${var.worker_cluster_label}"
    namespace = var.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "app.kubernetes.io/part-of"      = "gitops-demo"
    }
  }

  data = {
    name   = var.worker_cluster_label
    server = data.aws_ssm_parameter.worker_api_endpoint.value
    config = jsonencode({
      bearerToken = data.aws_ssm_parameter.worker_token.value
      tlsClientConfig = {
        caData = data.aws_ssm_parameter.worker_ca_cert.value
      }
    })
  }

  depends_on = [kustomization_resource.argocd_p2]
}

# ── ArgoCD Self-Managed Application Bootstrap ──────────────────────────────
# Terraform 完成 ArgoCD 安裝後，自動套用 argocd-app.yaml，
# 讓 ArgoCD 透過 GitOps 管理自己的安裝（self-managed bootstrap）。
# triggers：argocd-app.yaml 內容異動時自動重新執行。

resource "local_sensitive_file" "mgmt_kubeconfig" {
  content         = local.mgmt_kubeconfig_yaml
  filename        = "${path.root}/.bootstrap.kubeconfig"
  file_permission = "0600"
}

resource "null_resource" "argocd_self_app" {
  triggers = {
    manifest_sha256 = filesha256("${local.manifest_root}/bootstrap/argocd-app.yaml")
  }

  provisioner "local-exec" {
    command = "kubectl apply -n ${var.argocd_namespace} -f \"${local.manifest_root}/bootstrap/argocd-app.yaml\""
    environment = {
      KUBECONFIG = abspath(local_sensitive_file.mgmt_kubeconfig.filename)
    }
  }

  depends_on = [
    local_sensitive_file.mgmt_kubeconfig,
    kustomization_resource.argocd_p2,
  ]
}

# ── Root Application Bootstrap（環境入口點）────────────────────────────────────
# 套用對應環境的 Root Application（App of Apps），讓 ArgoCD 開始管理該環境的所有應用。
# 須在 argocd_self_app 之後執行，確保 ArgoCD CRD 已就緒。
# triggers：manifest 內容異動時自動重新執行。

resource "null_resource" "argocd_root_app" {
  for_each = var.root_app_teams

  triggers = {
    manifest_sha256 = filesha256("${local.manifest_root}/bootstrap/${each.value}")
  }

  provisioner "local-exec" {
    command = "kubectl apply -n ${var.argocd_namespace} -f \"${local.manifest_root}/bootstrap/${each.value}\""
    environment = {
      KUBECONFIG = abspath(local_sensitive_file.mgmt_kubeconfig.filename)
    }
  }

  depends_on = [
    null_resource.argocd_self_app,
  ]
}

