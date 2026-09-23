locals {
  efs_volume_name = "chroma-data"

  # The image ships no curl, so the probe uses the bundled Python instead.
  webapp_health_check_command = "python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:${var.webapp_port}/healthz', timeout=3)\""
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_cluster" "this" {
  name = "${var.project}-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]
}

resource "aws_ecs_task_definition" "chromadb" {
  family                   = "${var.project}-chromadb"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.ecs_task_cpu)
  memory                   = tostring(var.ecs_task_memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  volume {
    name = local.efs_volume_name

    efs_volume_configuration {
      file_system_id      = aws_efs_file_system.chroma.id
      transit_encryption  = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.chroma.id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "chromadb"
      image     = var.chroma_image
      essential = true

      portMappings = [
        { containerPort = var.chroma_port, protocol = "tcp" }
      ]

      mountPoints = [
        { sourceVolume = local.efs_volume_name, containerPath = var.chroma_data_path }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "chromadb"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "chroma" {
  name            = "${var.project}-chroma-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.chromadb.arn
  desired_count   = 0
  launch_type     = "FARGATE"

  depends_on = [aws_ecs_cluster_capacity_providers.this]

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.chroma.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.chroma.arn
  }

  # desired_count is toggled at runtime by the start-project/run-pipeline
  # workflows; Terraform must not fight that scaling on subsequent applies.
  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_ecs_task_definition" "webapp" {
  family                   = "${var.project}-webapp"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.webapp_task_cpu)
  memory                   = tostring(var.webapp_task_memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.webapp_task.arn

  container_definitions = jsonencode([
    {
      name      = "webapp"
      image     = "${aws_ecr_repository.webapp.repository_url}:${var.webapp_image_tag}"
      essential = true

      portMappings = [
        { containerPort = var.webapp_port, protocol = "tcp" }
      ]

      environment = [
        # The application defaults to 127.0.0.1, which is unreachable in a task.
        { name = "WEB_HOST", value = "0.0.0.0" },
        { name = "WEB_PORT", value = tostring(var.webapp_port) },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "CHROMA_HOST", value = "${aws_service_discovery_service.chroma.name}.${local.internal_dns_namespace}" },
        { name = "CHROMA_PORT", value = tostring(var.chroma_port) },
        { name = "CHROMA_COLLECTION", value = var.chroma_collection },
        { name = "LLM_MODEL_ID", value = var.llm_model_id },
        { name = "TOP_K", value = tostring(var.webapp_top_k) },
        { name = "OVERFETCH_FACTOR", value = tostring(var.webapp_overfetch_factor) },
        { name = "FILTER_WEIGHT", value = tostring(var.webapp_filter_weight) },
        { name = "RECENCY_WEIGHT", value = tostring(var.webapp_recency_weight) },
        { name = "RECENCY_WINDOW_YEARS", value = tostring(var.webapp_recency_window_years) },
        { name = "MAX_CONTEXT_TOKENS", value = tostring(var.webapp_max_context_tokens) },
        { name = "RESPONSE_TOKEN_BUFFER", value = tostring(var.webapp_response_token_buffer) },
        { name = "LOG_LEVEL", value = var.webapp_log_level },
        { name = "RATE_LIMIT_PER_MINUTE", value = tostring(var.webapp_rate_limit_per_minute) },
        { name = "RATE_LIMIT_PER_HOUR", value = tostring(var.webapp_rate_limit_per_hour) },
        # The task is only reachable through the API Gateway, so the client
        # address always arrives in X-Forwarded-For.
        { name = "TRUST_FORWARDED_FOR", value = tostring(var.webapp_trust_forwarded_for) },
        { name = "CORS_ALLOWED_ORIGINS", value = join(",", var.webapp_cors_allowed_origins) },
        { name = "CONVERSATION_TTL_SECONDS", value = tostring(var.webapp_conversation_ttl_seconds) },
        { name = "MAX_CONVERSATIONS", value = tostring(var.webapp_max_conversations) },
      ]

      # Cloud Map keeps the instance UNHEALTHY until this probe succeeds, so
      # API Gateway only routes to a task that is actually serving.
      healthCheck = {
        command     = ["CMD-SHELL", local.webapp_health_check_command]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "webapp"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "webapp" {
  name            = "${var.project}-webapp-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.webapp.arn
  desired_count   = 0
  launch_type     = "FARGATE"

  depends_on = [aws_ecs_cluster_capacity_providers.this]

  # The public IP only serves outbound traffic (ECR, Bedrock, CloudWatch);
  # inbound is limited to the API Gateway VPC link by the security group.
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.webapp.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.webapp.arn
    container_name = "webapp"
    container_port = var.webapp_port
  }

  # desired_count only ever toggles between 0 and 1 at runtime, and the deploy
  # workflow registers new task definition revisions; Terraform ignores both.
  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}
