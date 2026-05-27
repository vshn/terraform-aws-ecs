output "ecr_repository_urls" {
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
  description = "Map of ECR repository URLs keyed by repository name"
}

output "ecr_repository_arns" {
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
  description = "Map of ECR repository ARNs keyed by repository name"
}

output "cluster_id" {
  value       = aws_ecs_cluster.this.id
  description = "ECS cluster ID"
}

output "cluster_name" {
  value       = aws_ecs_cluster.this.name
  description = "ECS cluster name"
}

output "task_execution_role_arn" {
  value       = aws_iam_role.task_execution_role.arn
  description = "ARN of the task execution role"
}

output "task_role_arn" {
  value       = aws_iam_role.task_role.arn
  description = "ARN of the ECS task role (used by the application)"
}

output "scheduler_role_arn" {
  value       = aws_iam_role.task_scheduler_role.arn
  description = "ARN of the ECS task scheduler role (used by cronjobs)"
}
