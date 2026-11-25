resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # Repos created after 15 July 2026 send the immutable sub format:
  # repo:OWNER@OWNER_ID/REPO@REPO_ID:<context>
  sub_prefix = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"

  sub_pull_request = "${local.sub_prefix}:pull_request"
  sub_main         = "${local.sub_prefix}:ref:refs/heads/main"
  sub_environment  = "${local.sub_prefix}:environment:${var.environment}"
}
