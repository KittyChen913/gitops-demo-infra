# Bootstrap 環境使用 local backend。
# Bootstrap 負責建立 S3 bucket 本身，因此不能使用 S3 backend（雞生蛋問題）。
# CI 不持久化此 bootstrap state；既有 bucket 的安全設定由 workflow 冪等校正。

terraform {
  backend "local" {}
}
