locals {
  efs_ap_arns = distinct(compact(var.efs_access_point_arns))
}

# ------------------------------------------------------------------------------
# ECR Repositories
# ------------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  for_each             = toset(var.ecr_repo_names)
  name                 = each.value
  force_delete         = true
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1,
      description  = "Keep last 30 images",
      selection = {
        tagStatus   = "any",
        countType   = "imageCountMoreThan",
        countNumber = 30
      },
      action = {
        type = "expire"
      }
    }]
  })
}

# ------------------------------------------------------------------------------
# IAM Trust Policies
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    # Confused-deputy protection: only assume on behalf of resources in this account.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "scheduler_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    # Confused-deputy protection: only assume on behalf of resources in this account.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "task_execution_secrets" {
  count = length(var.secret_arns) > 0 ? 1 : 0
  statement {
    sid    = "GetSpecificSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = var.secret_arns
  }
}

data "aws_iam_policy_document" "task_execution_ssm" {
  count = length(var.parameter_arns) > 0 ? 1 : 0
  statement {
    sid    = "GetSpecificParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = var.parameter_arns
  }
}

data "aws_iam_policy_document" "task_role_ssm" {
  statement {
    sid    = "EcsExecSsmMessages"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }
}

# ------------------------------------------------------------------------------
# Task Execution Role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "task_execution_role" {
  name_prefix        = "${var.cluster_name}-task-exec-"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

resource "aws_iam_role_policy_attachment" "task_execution_role_policy" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Split secrets and SSM parameters into separate policies so they can be 
# conditionally created without rendering empty resource blocks in IAM.

resource "aws_iam_role_policy" "task_execution_secrets" {
  count = length(var.secret_arns) > 0 ? 1 : 0
  name  = "${var.cluster_name}-task-exec-secrets"
  role  = aws_iam_role.task_execution_role.id

  policy = data.aws_iam_policy_document.task_execution_secrets[0].json
}

resource "aws_iam_role_policy" "task_execution_ssm" {
  count  = length(var.parameter_arns) > 0 ? 1 : 0
  name   = "${var.cluster_name}-task-exec-ssm"
  role   = aws_iam_role.task_execution_role.id
  policy = data.aws_iam_policy_document.task_execution_ssm[0].json
}

# ------------------------------------------------------------------------------
# Task Role (Container Runtime)
# ------------------------------------------------------------------------------

resource "aws_iam_role" "task_role" {
  name_prefix        = "${var.cluster_name}-task-role-"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

resource "aws_iam_role_policy_attachment" "task_role_external_policies" {
  for_each   = toset(var.ecs_task_role_policy_arns)
  role       = aws_iam_role.task_role.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "task_role_ssm" {
  name   = "${var.cluster_name}-task-role-ecs-exec"
  role   = aws_iam_role.task_role.id
  policy = data.aws_iam_policy_document.task_role_ssm.json
}

# Conditionally construct and attach the EFS Access Point policy

data "aws_iam_policy_document" "efs_ap" {
  count = length(local.efs_ap_arns) > 0 ? 1 : 0

  statement {
    sid    = "AllowClientMountViaAP"
    effect = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:ClientRootAccess"
    ]
    resources = local.efs_ap_arns
  }
}

resource "aws_iam_role_policy" "task_role_efs_ap" {
  count  = length(local.efs_ap_arns) > 0 ? 1 : 0
  name   = "${var.cluster_name}-task-role-efs-ap"
  role   = aws_iam_role.task_role.id
  policy = data.aws_iam_policy_document.efs_ap[0].json
}

# ------------------------------------------------------------------------------
# EventBridge Scheduler Role
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "scheduler_run_task" {
  statement {
    sid     = "RunTaskDefinition"
    effect  = "Allow"
    actions = ["ecs:RunTask"]
    resources = [
      "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:task-definition/*"
    ]
  }

  statement {
    sid     = "PassServiceTaskRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.task_execution_role.arn,
      aws_iam_role.task_role.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_scheduler_role" {
  name_prefix        = "${var.cluster_name}-scheduler-role-"
  assume_role_policy = data.aws_iam_policy_document.scheduler_trust.json
}

resource "aws_iam_role_policy" "task_scheduler_role_policy" {
  name   = "${var.cluster_name}-scheduler-run-task"
  role   = aws_iam_role.task_scheduler_role.id
  policy = data.aws_iam_policy_document.scheduler_run_task.json
}

# ------------------------------------------------------------------------------
# ECS Cluster
# ------------------------------------------------------------------------------

resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# ------------------------------------------------------------------------------
# Logging and Monitoring
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ecs_cluster_logs" {
  name              = "/ecs/${var.cluster_name}"
  retention_in_days = var.log_retention # Make this a variable if you want flexibility
}
