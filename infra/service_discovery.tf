locals {
  internal_dns_namespace = "${var.project}.internal"
}

# Fargate task IPs change on every start, so both services are registered in a
# private DNS namespace instead of being discovered by IP.
resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = local.internal_dns_namespace
  description = "Internal service discovery for ${var.project}"
  vpc         = data.aws_vpc.default.id
}

resource "aws_service_discovery_service" "chroma" {
  name          = "chroma"
  force_destroy = true

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.internal.id
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# API Gateway resolves this service via DiscoverInstances and needs the port,
# which ECS only registers for SRV records.
resource "aws_service_discovery_service" "webapp" {
  name          = "webapp"
  force_destroy = true

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.internal.id
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "SRV"
      ttl  = 10
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
