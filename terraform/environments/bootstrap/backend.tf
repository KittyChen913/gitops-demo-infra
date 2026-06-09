# Bootstrap 環境使用 local backend。
# Bootstrap 負責建立 S3 bucket 本身，因此不能使用 S3 backend（雞生蛋問題）。
# State 在 CI 中由 GitHub Actions cache 持久化。

terraform {
  backend "local" {}
}
