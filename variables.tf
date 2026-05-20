variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster"
}

variable "ecr_repo_names" {
  type        = list(string)
  description = "List of ECR repository names"
  default     = []
}

variable "secret_arns" {
  type        = list(string)
  description = "List of secret arns to grant access"
}

variable "parameter_arns" {
  type        = list(string)
  description = "List of parameter arns to grant access"
}

variable "ecs_task_role_policy_arns" {
  type        = list(string)
  default     = []
  description = "List of additional IAM policy ARNs to attach to the ECS task role."
}

variable "efs_access_point_arns" {
  description = "List of EFS Access Point ARNs this service should be allowed to mount"
  type        = list(string)
  default     = []
}

variable "log_retention" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}