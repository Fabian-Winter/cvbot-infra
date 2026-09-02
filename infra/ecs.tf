locals {
  efs_volume_name = "chroma-data"
}

resource "aws_cloudwatch_log_group" "chromadb" {
  name = "/ecs/${var.project}-chromadb"
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

      environment = [
        { name = "PERSIST_DIRECTORY", value = var.chroma_data_path }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.chromadb.name
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

  # desired_count is toggled at runtime by the start-project/run-pipeline
  # workflows; Terraform must not fight that scaling on subsequent applies.
  lifecycle {
    ignore_changes = [desired_count]
  }
}
