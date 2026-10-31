terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Runs against Moto (https://github.com/getmoto/moto), an open-source AWS emulator started as a
# service container in CI. No AWS account or credentials are needed; state is local and throwaway.
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

module "demo" {
  source = "../../modules/demo"
}

output "security_group_id" {
  value = module.demo.security_group_id
}

output "bucket" {
  value = module.demo.bucket
}

output "log_group" {
  value = module.demo.log_group
}
