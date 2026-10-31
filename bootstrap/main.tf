# One-time setup of a personal AWS account for the tfscout demo. Run locally with admin credentials:
#
#   cd bootstrap
#   terraform init
#   terraform apply -var budget_email=you@example.com
#
# Then copy the printed `gh variable set` commands. State of this directory stays local (bootstrap/terraform.tfstate).
#
# Everything here and in envs/aws is free: no EC2/RDS/NAT, an empty S3 bucket, on-demand DynamoDB without traffic.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "github_repo" {
  description = "Repository whose workflows may assume the roles"
  type        = string
  default     = "mikonoid/tfscout-demo"
}

variable "create_oidc_provider" {
  description = "Set to false if token.actions.githubusercontent.com already exists in the account"
  type        = bool
  default     = true
}

variable "budget_email" {
  description = "If set, creates a $1 monthly budget that emails you on any actual or forecasted spend"
  type        = string
  default     = ""
}

data "aws_caller_identity" "current" {}

locals {
  account   = data.aws_caller_identity.current.account_id
  oidc_host = "token.actions.githubusercontent.com"
  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : (
    "arn:aws:iam::${local.account}:oidc-provider/${local.oidc_host}"
  )
  prefix = "tfscout-demo"
}

# --- Terraform state ------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket        = "${local.prefix}-tfstate-${local.account}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- GitHub OIDC ----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "trust_any_ref" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

data "aws_iam_policy_document" "trust_main_only" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

# Needed by both roles to read SSM SecureString parameters (encrypted with the AWS-managed aws/ssm key).
data "aws_iam_policy_document" "ssm_kms" {
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.us-east-1.amazonaws.com"]
    }
  }
}

# --- Plan role: read-only, any branch / pull request ------------------------------------------

resource "aws_iam_role" "plan" {
  name               = "${local.prefix}-plan"
  assume_role_policy = data.aws_iam_policy_document.trust_any_ref.json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_ssm_kms" {
  name   = "ssm-securestring"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.ssm_kms.json
}

# --- Apply role: main branch only, scoped to tfscout-demo-* resources ------------------------

data "aws_iam_policy_document" "apply" {
  statement {
    sid       = "Read"
    actions   = ["ec2:Describe*", "ssm:DescribeParameters", "logs:DescribeLogGroups", "iam:ListPolicies"]
    resources = ["*"]
  }
  statement {
    sid = "Network"
    actions = [
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress", "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:ModifySecurityGroupRules", "ec2:CreateTags", "ec2:DeleteTags",
    ]
    resources = ["*"]
  }
  statement {
    sid     = "Storage"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${local.prefix}-*",
      "arn:aws:s3:::${local.prefix}-*/*",
    ]
  }
  statement {
    sid       = "Dynamo"
    actions   = ["dynamodb:*"]
    resources = ["arn:aws:dynamodb:us-east-1:${local.account}:table/${local.prefix}-*"]
  }
  statement {
    sid     = "Iam"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::${local.account}:role/${local.prefix}-*",
      "arn:aws:iam::${local.account}:policy/${local.prefix}-*",
    ]
  }
  statement {
    sid       = "Ssm"
    actions   = ["ssm:*"]
    resources = ["arn:aws:ssm:us-east-1:${local.account}:parameter/${local.prefix}/*"]
  }
  statement {
    sid       = "Logs"
    actions   = ["logs:*"]
    resources = ["arn:aws:logs:us-east-1:${local.account}:log-group:/${local.prefix}/*"]
  }
}

resource "aws_iam_role" "apply" {
  name               = "${local.prefix}-apply"
  assume_role_policy = data.aws_iam_policy_document.trust_main_only.json
}

resource "aws_iam_role_policy" "apply" {
  name   = "tfscout-demo-resources"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}

resource "aws_iam_role_policy" "apply_ssm_kms" {
  name   = "ssm-securestring"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.ssm_kms.json
}

# --- Cost guard -----------------------------------------------------------------------------

resource "aws_budgets_budget" "guard" {
  count        = var.budget_email == "" ? 0 : 1
  name         = "${local.prefix}-guard"
  budget_type  = "COST"
  limit_amount = "1"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 1
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}

# --- Outputs --------------------------------------------------------------------------------

output "github_variables" {
  description = "Run these to configure the demo repository"
  value       = <<-EOT
    gh variable set AWS_PLAN_ROLE_ARN  -R ${var.github_repo} -b ${aws_iam_role.plan.arn}
    gh variable set AWS_APPLY_ROLE_ARN -R ${var.github_repo} -b ${aws_iam_role.apply.arn}
    gh variable set TF_STATE_BUCKET    -R ${var.github_repo} -b ${aws_s3_bucket.state.id}
  EOT
}
