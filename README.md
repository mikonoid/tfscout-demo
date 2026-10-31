# tfscout-demo

A playground for [tfscout](https://github.com/mikonoid/tfscout), the Terraform plan review and drift
detection GitHub Action.

The same Terraform module ([modules/demo](modules/demo/main.tf): VPC, security group, S3, DynamoDB, IAM,
SSM, CloudWatch Logs) is deployed to two environments:

| Environment | Where | Needs |
|---|---|---|
| [envs/moto](envs/moto/main.tf) | [Moto](https://github.com/getmoto/moto), an AWS emulator started inside the workflow | nothing |
| [envs/aws](envs/aws/main.tf) | a real AWS account (free tier, nothing billable) | a one-time [bootstrap](bootstrap/main.tf) |

## Moto (no AWS account)

**Pull request review.** Every PR that changes `modules/` or `envs/moto/` runs
[moto-review.yml](.github/workflows/moto-review.yml): Moto is started, `main` is applied as "production",
the PR is planned against it and tfscout comments on the PR.

Things to try in a PR:

| Change in `modules/demo/main.tf` | Expected finding |
|---|---|
| Add an `ingress` block for port 22 from `0.0.0.0/0` | critical: ingress opened to the internet |
| Set the IAM policy to `Action = "*"`, `Resource = "*"` | critical: IAM wildcard |
| Rename the DynamoDB table | critical: stateful resource replaced, forced by `name` |
| Set `block_public_policy = false` | high: S3 public access guard disabled |
| Change a tag | no findings, only the summary |

**Drift.** Run [moto-drift.yml](.github/workflows/moto-drift.yml) from the Actions tab. With
`simulate: drift` it applies `main`, makes three manual changes (SSH opened, S3 public access block
disabled, log retention changed) and tfscout opens an issue. `simulate: no-drift` closes it.

## Real AWS account

### One-time setup

With admin credentials for your account (e.g. `aws configure` or `aws sso login`):

```bash
cd bootstrap
terraform init
terraform apply -var budget_email=you@example.com   # budget_email is optional
```

This creates, in `us-east-1`:

- an S3 bucket for Terraform state;
- the GitHub OIDC provider, so workflows get short-lived credentials and no keys are stored;
- `tfscout-demo-plan`: read-only role, usable from any branch or pull request;
- `tfscout-demo-apply`: usable only from `main`, limited to `tfscout-demo-*` resources and unable to
  start EC2 instances or anything else that costs money;
- optionally a $1/month budget that emails you if anything is ever charged.

Run the `gh variable set ...` commands it prints. The AWS workflows stay disabled until these variables exist.

### Workflows

| Workflow | Trigger | Role | What it does |
|---|---|---|---|
| [aws-apply.yml](.github/workflows/aws-apply.yml) | push to `main`, manual | apply | `terraform apply` |
| [aws-review.yml](.github/workflows/aws-review.yml) | pull request | plan | plan + tfscout comment |
| [aws-drift.yml](.github/workflows/aws-drift.yml) | weekdays 06:00 UTC, manual | plan (+ apply to simulate) | refresh-only plan + tfscout issue |
| [aws-destroy.yml](.github/workflows/aws-destroy.yml) | manual, type `destroy` | apply | removes the demo resources |

A typical session:

1. Run **aws apply** once to create the resources.
2. Open a PR that changes `modules/demo/main.tf` and read both comments (`moto` and `aws`).
3. Change something in the AWS console (for example add an inbound rule to `tfscout-demo-web`), or run
   **aws drift** with `simulate` checked. An issue appears.
4. Run **aws apply** to revert the drift, then **aws drift** again. The issue is closed.
5. When you are done, run **aws destroy**. To remove the bootstrap as well: `cd bootstrap && terraform destroy`.

## Run locally with Moto

```bash
docker run -d --rm -p 5055:5000 motoserver/moto:5.2.5    # port 5000 is taken by AirPlay on macOS
cd envs/moto
export TF_VAR_aws_endpoint=http://localhost:5055
terraform init && terraform apply -auto-approve
AWS_ENDPOINT=http://localhost:5055 ../../scripts/simulate-drift.sh envs/moto
terraform plan -refresh-only -out=drift.tfplan
pip install tfscout && tfscout drift drift.tfplan
```
