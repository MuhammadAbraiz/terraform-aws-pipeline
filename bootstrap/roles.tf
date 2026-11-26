locals {
  account_id  = data.aws_caller_identity.current.account_id
  site_bucket = "arn:aws:s3:::${var.project}-site-${local.account_id}"
  state_arn   = aws_s3_bucket.state.arn
  token       = "token.actions.githubusercontent.com"
}

# ---------- Trust policies ----------

# Plan role: pull requests and pushes to main. Never the environment.
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.token}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.token}:sub"
      values   = [local.sub_pull_request, local.sub_main]
    }
  }
}

# Apply role: only jobs in the production environment, running on main.
data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.token}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.token}:sub"
      values   = [local.sub_environment]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.token}:ref"
      values   = ["refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.project}-plan"
  description          = "Terraform plan from pull requests and main. Read-only."
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role" "apply" {
  name                 = "${var.project}-apply"
  description          = "Terraform apply from the approved production environment."
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

# ---------- Shared pieces ----------

data "aws_iam_policy_document" "state_common" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [local.state_arn]
  }
  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_arn}/${local.state_key}"]
  }
  statement {
    sid       = "StateLockFile"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_arn}/${local.state_key}.tflock"]
  }
}

# ---------- Plan role ----------

data "aws_iam_policy_document" "plan" {
  source_policy_documents = [data.aws_iam_policy_document.state_common.json]

  statement {
    sid       = "UploadSavedPlans"
    actions   = ["s3:PutObject"]
    resources = ["${local.state_arn}/${local.plans_prefix}*"]
  }

  statement {
    sid = "ReadSiteBucket"
    actions = [
      "s3:GetBucket*",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetAccelerateConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:ListBucket",
    ]
    resources = [local.site_bucket, "${local.site_bucket}/*"]
  }

  statement {
    sid       = "ReadOwnDistributions"
    actions   = ["cloudfront:GetDistribution", "cloudfront:GetDistributionConfig", "cloudfront:ListTagsForResource"]
    resources = ["arn:aws:cloudfront::${local.account_id}:distribution/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project]
    }
  }

  statement {
    sid = "ReadCloudFrontPoliciesAndOac"
    actions = [
      "cloudfront:GetOriginAccessControl",
      "cloudfront:ListOriginAccessControls",
      "cloudfront:GetCachePolicy",
      "cloudfront:ListCachePolicies",
      "cloudfront:GetResponseHeadersPolicy",
      "cloudfront:ListResponseHeadersPolicies",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "plan"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

# ---------- Apply role ----------

data "aws_iam_policy_document" "apply" {
  source_policy_documents = [data.aws_iam_policy_document.state_common.json]

  statement {
    sid       = "WriteState"
    actions   = ["s3:PutObject"]
    resources = ["${local.state_arn}/${local.state_key}"]
  }

  statement {
    sid       = "ReadSavedPlans"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_arn}/${local.plans_prefix}*"]
  }

  statement {
    sid       = "ManageSiteBucket"
    actions   = ["s3:*"]
    resources = [local.site_bucket, "${local.site_bucket}/*"]
  }

  statement {
    sid       = "CreateTaggedDistributions"
    actions   = ["cloudfront:CreateDistribution", "cloudfront:TagResource"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project]
    }
  }

  statement {
    sid = "ManageOwnDistributions"
    actions = [
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:ListTagsForResource",
      "cloudfront:UntagResource",
      "cloudfront:CreateInvalidation",
    ]
    resources = ["arn:aws:cloudfront::${local.account_id}:distribution/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project]
    }
  }

  statement {
    sid = "ManageOacAndReadPolicies"
    actions = [
      "cloudfront:CreateOriginAccessControl",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
      "cloudfront:ListOriginAccessControls",
      "cloudfront:GetCachePolicy",
      "cloudfront:ListCachePolicies",
      "cloudfront:GetResponseHeadersPolicy",
      "cloudfront:ListResponseHeadersPolicies",
      "cloudfront:CreateResponseHeadersPolicy",
      "cloudfront:UpdateResponseHeadersPolicy",
      "cloudfront:DeleteResponseHeadersPolicy",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "apply"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}
