# ECS Shared Base Module

## Overview

This reusable module creates the shared ECS foundation that is consumed by each environment-specific stack. It provisions the cluster control plane, ECR repositories for the Drupal images, IAM roles required by tasks and the EventBridge Scheduler, and optional access permissions to supporting AWS services (Secrets Manager, SSM Parameter Store, EFS access points and S3 buckets).

## Architecture

The module defines the following building blocks:

- An ECS cluster configured for Fargate workloads.
- A configurable set of ECR repositories to host container images.
- IAM roles and policies for ECS task execution, application task access, and EventBridge Scheduler to trigger one-off tasks.
- Optional IAM permissions to read secrets, parameters, mount EFS access points, and access S3 buckets provided by the caller.

The module is stateless: all environment specific wiring (such as subnet selection, security groups or task definitions) happens in the consuming stack.

## Inputs

| Name                        | Description                                                           | Type              | Default  | Required |
|-----------------------------|-----------------------------------------------------------------------|-------------------|----------|----------|
| `cluster_name`              | Name of the ECS cluster                                               | `string`          | `None`   | yes      |
| `ecr_repo_names`            | List of ECR repository names                                          | `${list(string)}` | `[]`     | yes      |
| `secret_arns`               | List of secret arns to grant access                                   | `${list(string)}` | `None`   | yes      |
| `parameter_arns`            | List of parameter arns to grant access                                | `${list(string)}` | `None`   | yes      |
| `ecs_task_role_policy_arns` | List of additional IAM policy ARNs to attach to the ECS task role.    | `${list(string)}` | `[]`     | yes      |
| `efs_access_point_arns`     | List of EFS Access Point ARNs this service should be allowed to mount | `${list(string)}` | `[]`     | yes      |
| `tags`                      | Common tags                                                           | `${map(string)}`  | `{}`     | yes      |

## Outputs

| Name | Description |
| --- | --- |
| `ecr_repository_urls` | Map of ECR repository URLs keyed by repository name |
| `ecr_repository_arns` | Map of ECR repository ARNs keyed by repository name |
| `cluster_id` | ECS cluster ID |
| `cluster_name` | ECS cluster name |
| `task_execution_role_arn` | ARN of the task execution role |
| `task_role_arn` | ARN of the ECS task role (used by the application) |
| `scheduler_role_arn` | ARN of the ECS task scheduler role (used by cronjobs) |

## Usage

The environment stacks call this module and pass in their networking, storage and IAM dependencies. The outputs are later used to create ECS services.
