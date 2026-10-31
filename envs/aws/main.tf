terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The bucket comes from bootstrap/ and is passed at init time:
  #   terraform init -backend-config="bucket=<state bucket>"
  backend "s3" {
    key          = "tfscout-demo/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

module "demo" {
  source      = "../../modules/demo"
  name_suffix = "-${data.aws_caller_identity.current.account_id}"
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
