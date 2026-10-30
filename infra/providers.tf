terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# The demo runs against Moto (https://github.com/getmoto/moto), an open-source AWS emulator started
# as a service container in CI, so no AWS account or credentials are needed.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    dynamodb = var.aws_endpoint
    ec2      = var.aws_endpoint
    iam      = var.aws_endpoint
    logs     = var.aws_endpoint
    s3       = var.aws_endpoint
    ssm      = var.aws_endpoint
    sts      = var.aws_endpoint
  }
}

variable "aws_endpoint" {
  description = "AWS API endpoint (Moto)"
  type        = string
  default     = "http://localhost:5000"
}
