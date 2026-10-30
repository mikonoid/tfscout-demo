# tfscout-demo

Live playground for [tfscout](https://github.com/mikonoid/tfscout), the AI-assisted Terraform plan review and
drift detection GitHub Action.

**No AWS account needed.** The Terraform code in [infra/](infra/) creates real AWS resource types (VPC,
security group, S3, DynamoDB, IAM, SSM, CloudWatch Logs), but in CI they are created in
[Moto](https://github.com/getmoto/moto), an open-source AWS emulator that runs as a service container.

## 1. Pull request review

Every PR that touches `infra/` triggers [tfscout-review.yml](.github/workflows/tfscout-review.yml):

```
Moto (fresh)  →  terraform apply  (main = "production")
              →  terraform plan   (your PR)
              →  tfscout review   → comment on the PR
```

Try it: open a PR that does something dangerous, for example:

| Change in `infra/main.tf` | Expected finding |
|---|---|
| Add an `ingress` block for port 22 from `0.0.0.0/0` | 🔴 critical: ingress opened to the internet |
| Set the IAM policy to `Action = "*"`, `Resource = "*"` | 🔴 critical: IAM wildcard |
| Rename the DynamoDB table | 🔴 critical: stateful resource REPLACED, forced by `name` |
| Set `block_public_policy = false` | 🟠 high: S3 public access guard disabled |
| Change a tag | ✅ no risks, AI summary only |

Push another commit to the same PR and the comment is **updated in place**.

## 2. Drift detection

Run [tfscout-drift.yml](.github/workflows/tfscout-drift.yml) from the **Actions** tab:

```
Moto (fresh)  →  terraform apply
              →  scripts/simulate-drift.sh   ("someone changed prod by hand")
              →  terraform plan -refresh-only
              →  tfscout drift   → GitHub issue
```

| Run with | Result |
|---|---|
| `simulate: drift` | Issue **"Terraform drift detected: demo"** is created: SSH opened (🔴 risky), S3 public access block disabled (🔴 risky), log retention changed (🟡 manual-change) |
| `simulate: drift` again | Same drift → issue is **not** spammed |
| `simulate: no-drift` | Issue is **closed** as resolved |

## Using it in your own repository

The steps between the `-----` markers in the workflows are the only part you need. Everything else here
just simulates "production". See the [tfscout setup guide](https://github.com/mikonoid/tfscout/blob/main/docs/setup.md).

## Run locally

```bash
docker run -d --rm -p 5055:5000 motoserver/moto:5.2.5    # port 5000 is taken by AirPlay on macOS
cd infra
export TF_VAR_aws_endpoint=http://localhost:5055
terraform init && terraform apply -auto-approve
AWS_ENDPOINT=http://localhost:5055 ../scripts/simulate-drift.sh
terraform plan -refresh-only -out=drift.tfplan
pip install git+https://github.com/mikonoid/tfscout && tfscout drift drift.tfplan
```
