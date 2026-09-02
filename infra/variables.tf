variable "project" {
  description = "Short project name used as a prefix for all resource names."
  type        = string
  default     = "cvbot"
}

variable "aws_region" {
  description = "AWS region the infrastructure is deployed to."
  type        = string
  default     = "eu-central-1"
}

variable "gh_owner" {
  description = "GitHub repository owner, used for the OIDC deploy role trust policy."
  type        = string
}

variable "gh_repo" {
  description = "GitHub repository name, used for the OIDC deploy role trust policy."
  type        = string
}

variable "gh_pat" {
  description = "GitHub PAT (repo Administration: Read & Write) used by the runner to self-register."
  type        = string
  sensitive   = true
}

variable "ec2_instance_type" {
  description = "Instance type of the self-hosted GitHub Actions runner."
  type        = string
  default     = "t3.small"
}

variable "chroma_image" {
  description = "Container image running ChromaDB."
  type        = string
  default     = "chromadb/chroma:1.5.9"
}

variable "chroma_port" {
  description = "Port ChromaDB listens on."
  type        = number
  default     = 8000
}

variable "efs_nfs_port" {
  description = "NFS port used by the EFS mount targets."
  type        = number
  default     = 2049
}

variable "efs_access_point_path" {
  description = "Root directory of the EFS access point."
  type        = string
  default     = "/chroma-data"
}

variable "chroma_data_path" {
  description = "Path the EFS volume is mounted at inside the ChromaDB container."
  type        = string
  default     = "/chroma/chroma"
}

variable "ecs_task_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 512
}

variable "ecs_task_memory" {
  description = "Fargate task memory (MiB)."
  type        = number
  default     = 1024
}

variable "runner_version" {
  description = "Version of the actions/runner release installed on the EC2 instance."
  type        = string
  default     = "2.319.1"
}

variable "runner_label" {
  description = "Label used to target the self-hosted runner from workflows."
  type        = string
  default     = "cvbot-runner"
}

variable "ami_ssm_parameter" {
  description = "SSM parameter name resolving to the AMI used for the runner instance."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
