#!/usr/bin/env bash
# Simulates "someone changed production by hand" against the Moto AWS emulator.
# Usage: scripts/simulate-drift.sh   (run after `terraform apply` in infra/)
set -euo pipefail

cd "$(dirname "$0")/../infra"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
aws_() { aws --endpoint-url "${AWS_ENDPOINT:-http://localhost:5000}" "$@"; }

sg=$(terraform output -raw security_group_id)
bucket=$(terraform output -raw bucket)
log_group=$(terraform output -raw log_group)

echo "1) Hotfix: someone opened SSH to the world on the web security group"
aws_ ec2 authorize-security-group-ingress --group-id "$sg" --protocol tcp --port 22 --cidr 0.0.0.0/0

echo "2) Cost tweak: someone lowered log retention from 30 to 7 days in the console"
aws_ logs put-retention-policy --log-group-name "$log_group" --retention-in-days 7

echo "3) Debugging: someone disabled the S3 public access block"
aws_ s3api put-public-access-block --bucket "$bucket" --public-access-block-configuration \
  BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

echo "Drift simulated."
