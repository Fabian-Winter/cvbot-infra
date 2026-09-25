resource "aws_apigatewayv2_vpc_link" "webapp" {
  name               = "${var.project}-vpc-link"
  subnet_ids         = data.aws_subnets.default.ids
  security_group_ids = [aws_security_group.webapp.id]
}

# Account-wide setting; required once before any stage can enable access logging.
resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigateway_cloudwatch.arn
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
  timeout_milliseconds   = 30000
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

# HTTP API (v2) stages check this resource policy, not the account role above,
# before allowing access logging to a log group.
resource "aws_cloudwatch_log_resource_policy" "apigateway" {
  policy_name = "${var.project}-apigateway-logs-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowApiGatewayLogging"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
        ]
        Resource = "${aws_cloudwatch_log_group.webapp_api.arn}:*"
      }
    ]
  })
}

# The $default stage keeps the request path unchanged; a named stage would be
# prepended to the backend path and break the app's routes.
resource "aws_apigatewayv2_stage" "webapp" {
  api_id      = aws_apigatewayv2_api.webapp.id
  name        = "$default"
  auto_deploy = true

  depends_on = [aws_api_gateway_account.this, aws_cloudwatch_log_resource_policy.apigateway]

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
