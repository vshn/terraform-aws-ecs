# Terraform Module for AWS ECS

Shared ECS Fargate foundation: cluster, optional ECR repositories, the IAM roles
tasks and scheduled jobs need, and a log group.

## Overview

Provisions the parts of an ECS setup that are identical across environments:

- **ECS cluster** for Fargate with Container Insights and
  `FARGATE`/`FARGATE_SPOT` capacity providers (`FARGATE` default, base 1).
- **ECR repositories** (optional) with scan-on-push, `force_delete` and a
  keep-last-30-images lifecycle policy.
- **Task execution role** — `AmazonECSTaskExecutionRolePolicy` plus read access
  to exactly the Secrets Manager secrets and SSM parameters the caller names.
  Each policy is only created when its input is non-empty.
- **Task role** — ECS Exec (`ssmmessages:*`), optional EFS access point mount
  permissions, and any additional policy ARNs the caller attaches.
- **EventBridge Scheduler role** — `ecs:RunTask` on `task-definition/*` plus
  `iam:PassRole` for the two roles above, restricted to
  `ecs-tasks.amazonaws.com`.
- **CloudWatch log group** `/ecs/<cluster_name>` with configurable retention.

Task definitions, services, subnets, security groups, load balancers and
autoscaling stay in the consuming stack; the module creates no networking.

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `cluster_name` | Cluster name, also the prefix for all IAM roles, policies and the log group | `string` | — | yes |
| `secret_arns` | Secrets Manager ARNs the task execution role may read (`[]` creates no policy) | `list(string)` | — | yes |
| `parameter_arns` | SSM parameter ARNs the task execution role may read (`[]` creates no policy) | `list(string)` | — | yes |
| `ecr_repo_names` | ECR repositories to create; leave empty if managed elsewhere | `list(string)` | `[]` | no |
| `ecr_image_tag_mutability` | `MUTABLE` or `IMMUTABLE` for the created repositories | `string` | `"MUTABLE"` | no |
| `ecs_task_role_policy_arns` | Additional IAM policy ARNs to attach to the task role | `list(string)` | `[]` | no |
| `efs_access_point_arns` | EFS access point ARNs the task role may mount | `list(string)` | `[]` | no |
| `log_retention` | Retention in days for `/ecs/<cluster_name>` | `number` | `30` | no |

## Outputs

| Name | Description |
|---|---|
| `cluster_id` | Cluster ID (the cluster ARN — use as a scheduler target) |
| `cluster_name` | Cluster name |
| `task_execution_role_arn` | Use as `execution_role_arn` in task definitions |
| `task_role_arn` | Use as `task_role_arn` in task definitions |
| `scheduler_role_arn` | Use as the `role_arn` of an EventBridge schedule target |
| `ecr_repository_urls` | Map of repository name → URL |
| `ecr_repository_arns` | Map of repository name → ARN |

## Usage

```hcl
module "ecs" {
  source = "git::https://github.com/vshn/terraform-aws-ecs.git?ref=v1.0.0"

  cluster_name = var.environment

  ecr_repo_names = ["app-php", "app-nginx"]

  secret_arns    = [module.aurora_database.db_secret_arn]
  parameter_arns = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/*"]

  ecs_task_role_policy_arns = [
    aws_iam_policy.s3_access.arn,
    aws_iam_policy.ses_access.arn,
  ]

  efs_access_point_arns = module.efs.efs_access_point_arns
  log_retention         = 365
}

resource "aws_ecs_task_definition" "app" {
  family             = "app"
  execution_role_arn = module.ecs.task_execution_role_arn
  task_role_arn      = module.ecs.task_role_arn
  # ...
}
```

## Development

CI runs `terraform init -backend=false`, `terraform validate` and
`terraform fmt -check -recursive -diff`.

Merging a pull request labelled `bump:major`, `bump:minor` or `bump:patch` tags
the merge commit and creates a GitHub release; without such a label no release
is cut. Scaffolding under `.github/`, `renovate.json` and `.gitignore` is managed
by [`terraform-module-template`](https://github.com/vshn/terraform-module-template)
via cruft — do not edit it directly.
