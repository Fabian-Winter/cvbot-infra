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

variable "gh_owner_id" {
  description = "GitHub repository owner ID, used for the OIDC deploy role trust policy."
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
  default     = "/data"
}

variable "ecs_task_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256
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

variable "log_retention_days" {
  description = "Retention of the CloudWatch log groups; keeps conversation traces from being stored indefinitely."
  type        = number
  default     = 7
}

# ---------------------------------------------------------------------------
# cvbot-retriever web application
# ---------------------------------------------------------------------------
variable "webapp_port" {
  description = "Port the cvbot-retriever web application listens on."
  type        = number
  default     = 8080
}

variable "webapp_image_tag" {
  description = "Image tag of the web application pulled from ECR."
  type        = string
  default     = "latest"
}

variable "webapp_task_cpu" {
  description = "Fargate task CPU units of the web application."
  type        = number
  default     = 256
}

variable "webapp_task_memory" {
  description = "Fargate task memory (MiB) of the web application."
  type        = number
  default     = 512
}

variable "ecr_image_retention_count" {
  description = "Number of web application images kept in ECR before the oldest ones expire."
  type        = number
  default     = 3
}

variable "webapp_throttle_rate_limit" {
  description = "Steady-state requests per second accepted by the API Gateway stage; caps Bedrock cost."
  type        = number
  default     = 5
}

variable "webapp_throttle_burst_limit" {
  description = "Burst capacity of the API Gateway stage throttling."
  type        = number
  default     = 10
}

# ---------------------------------------------------------------------------
# Web application runtime configuration (passed as container environment)
# ---------------------------------------------------------------------------
variable "chroma_collection" {
  description = "ChromaDB collection queried by the retriever; must match the one written by cvbot-embedder."
  type        = string
  default     = "cvbot_documents"
}

variable "llm_model_id" {
  description = "Bedrock model ID used to generate answers. Requires the eu.* cross-region inference profile in eu-central-1."
  type        = string
  default     = "eu.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "webapp_top_k" {
  description = "Number of chunks retrieved from ChromaDB per question."
  type        = number
  default     = 4
}

variable "webapp_overfetch_factor" {
  description = "How many times webapp_top_k is fetched before similarity, metadata filters and recency re-rank the candidates."
  type        = number
  default     = 4
}

variable "webapp_filter_weight" {
  description = "Largest ranking score the filter bonus adds, scaled by the share of matching metadata fields, relative to the similarity score of 0 to 1."
  type        = number
  default     = 0.2
}

variable "webapp_recency_weight" {
  description = "Largest ranking score the recency bonus adds, derived from the from/to/status metadata at query time. 0 disables it."
  type        = number
  default     = 0.2
}

variable "webapp_recency_window_years" {
  description = "How many years back the recency bonus decays linearly to zero."
  type        = number
  default     = 10
}

variable "webapp_max_context_tokens" {
  description = "Upper bound for the whole context sent to the LLM."
  type        = number
  default     = 32000
}

variable "webapp_response_token_buffer" {
  description = "Part of webapp_max_context_tokens kept free for the answer."
  type        = number
  default     = 2048
}

variable "webapp_log_level" {
  description = "Log level of the web application (DEBUG, INFO, WARNING, ERROR)."
  type        = string
  default     = "INFO"
}

# ---------------------------------------------------------------------------
# Web application hardening (passed as container environment)
# ---------------------------------------------------------------------------
variable "webapp_rate_limit_per_minute" {
  description = "Questions a single client may have answered per minute; the per-client counterpart of the API Gateway throttling."
  type        = number
  default     = 10
}

variable "webapp_rate_limit_per_hour" {
  description = "Questions a single client may have answered per hour."
  type        = number
  default     = 60
}

variable "webapp_trust_forwarded_for" {
  description = "Whether the application may read the client address from X-Forwarded-For. Required behind the API Gateway, which is the only way in."
  type        = bool
  default     = true
}

variable "webapp_cors_allowed_origins" {
  description = "Origins allowed to call the JSON API from a browser. Empty means same-origin only."
  type        = list(string)
  default     = []
}

variable "webapp_conversation_ttl_seconds" {
  description = "Idle time after which a conversation is dropped from the memory of the task."
  type        = number
  default     = 1800
}

variable "webapp_max_conversations" {
  description = "Upper bound of conversations the task keeps in memory at once."
  type        = number
  default     = 50
}

# ---------------------------------------------------------------------------
# Bedrock authorisation
# ---------------------------------------------------------------------------
variable "bedrock_foundation_model_ids" {
  description = "Foundation models the web application task may invoke. Inference profiles also require the underlying foundation model."
  type        = list(string)
  default     = ["amazon.titan-embed-text-v2:0", "anthropic.claude-haiku-4-5-20251001-v1:0"]
}

variable "bedrock_inference_profile_ids" {
  description = "Cross-region inference profiles the web application task may invoke."
  type        = list(string)
  default     = ["eu.anthropic.claude-haiku-4-5-20251001-v1:0"]
}
