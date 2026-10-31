terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "db_password" {
  description = "Demo secret; tfscout must never send it to the LLM"
  type        = string
  sensitive   = true
  default     = "Sup3r-Secret-Demo-Pass!"
}

variable "name_suffix" {
  description = "Appended to globally unique names (S3 buckets), e.g. the AWS account id"
  type        = string
  default     = ""
}

locals {
  name = "tfscout-demo"
  tags = {
    Project = local.name
    Owner   = "platform-team"
  }
}

# --- Network --------------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block = "10.20.0.0/16"
  tags       = merge(local.tags, { Name = local.name })
}

resource "aws_security_group" "web" {
  name        = "${local.name}-web"
  description = "Web tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from the corporate network"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# --- Storage --------------------------------------------------------------------------------

resource "aws_s3_bucket" "artifacts" {
  bucket = "${local.name}-artifacts${var.name_suffix}"
  # No tags here: the Moto emulator does not round-trip S3 bucket tags, which would show as a permanent diff.
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "orders" {
  name         = "${local.name}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  tags = local.tags
}

# --- Identity -------------------------------------------------------------------------------

resource "aws_iam_role" "ci" {
  name = "${local.name}-ci"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "codebuild.amazonaws.com" }
    }]
  })
  tags = local.tags
}

resource "aws_iam_policy" "ci" {
  name = "${local.name}-ci"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "${aws_s3_bucket.artifacts.arn}/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ci" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.ci.arn
}

# --- App config -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "db_password" {
  name  = "/${local.name}/db/password"
  type  = "SecureString"
  value = var.db_password
  tags  = local.tags
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${local.name}/app"
  retention_in_days = 30
  tags              = local.tags
}

# --- Outputs used by scripts/simulate-drift.sh ---------------------------------------------

output "security_group_id" {
  value = aws_security_group.web.id
}

output "bucket" {
  value = aws_s3_bucket.artifacts.id
}

output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}
