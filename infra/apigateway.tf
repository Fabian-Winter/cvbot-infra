resource "aws_apigatewayv2_vpc_link" "webapp" {
  name               = "${var.project}-vpc-link"
  subnet_ids         = data.aws_subnets.default.ids
  security_group_ids = [aws_security_group.webapp.id]
}

resource "aws_apigatewayv2_api" "webapp" {
  name          = "${var.project}-webapp-api"
  description   = "Public HTTPS entry point of the cvbot-retriever web application"
  protocol_type = "HTTP"
}

# Targets the Cloud Map service instead of a load balancer, which keeps the
# hourly cost at zero while the ECS service is scaled to 0.
resource "aws_apigatewayv2_integration" "webapp" {
  api_id                 = aws_apigatewayv2_api.webapp.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.webapp.id
  integration_uri        = aws_service_discovery_service.webapp.arn
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "webapp" {
  api_id    = aws_apigatewayv2_api.webapp.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.webapp.id}"
}

resource "aws_cloudwatch_log_group" "webapp_api" {
  name              = "/aws/apigateway/${var.project}-webapp"
  retention_in_days = var.log_retention_days
}

# The $default stage keeps the request path unchanged; a named stage would be
# prepended to the backend path and break the app's routes.
resource "aws_apigatewayv2_stage" "webapp" {
  api_id      = aws_apigatewayv2_api.webapp.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.webapp_api.arn

    # Metadata only, so no conversation content ends up in the logs.
    format = jsonencode({
      requestId        = "$context.requestId"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLatency  = "$context.responseLatency"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  # Infrastructure-level guard against runaway Bedrock cost; per-client rate
  # limiting stays in the application.
  default_route_settings {
    throttling_rate_limit  = var.webapp_throttle_rate_limit
    throttling_burst_limit = var.webapp_throttle_burst_limit
  }
}
