resource "aws_security_group" "runner" {
  name        = "${var.project}-runner-sg"
  description = "cvbot-embedder self-hosted runner"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_security_group" "chroma" {
  name        = "${var.project}-chroma-sg"
  description = "cvbot-embedder ChromaDB and EFS"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_security_group" "webapp" {
  name        = "${var.project}-webapp-sg"
  description = "cvbot-retriever web application and its API Gateway VPC link"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_egress_rule" "runner_all" {
  security_group_id = aws_security_group.runner.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "chroma_all" {
  security_group_id = aws_security_group.chroma.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# The task has no NAT gateway, so ECR, Bedrock and CloudWatch are reached
# outbound over the public subnet.
resource "aws_vpc_security_group_egress_rule" "webapp_all" {
  security_group_id = aws_security_group.webapp.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ChromaDB is only reachable from the runner and the web application, never
# from the public internet.
resource "aws_vpc_security_group_ingress_rule" "chroma_from_runner" {
  security_group_id            = aws_security_group.chroma.id
  ip_protocol                  = "tcp"
  from_port                    = var.chroma_port
  to_port                      = var.chroma_port
  referenced_security_group_id = aws_security_group.runner.id
}

resource "aws_vpc_security_group_ingress_rule" "chroma_from_webapp" {
  security_group_id            = aws_security_group.chroma.id
  ip_protocol                  = "tcp"
  from_port                    = var.chroma_port
  to_port                      = var.chroma_port
  referenced_security_group_id = aws_security_group.webapp.id
}

# The VPC link ENIs share this security group with the task; inbound is
# restricted to itself so the app is only reachable through the API Gateway.
resource "aws_vpc_security_group_ingress_rule" "webapp_from_vpc_link" {
  security_group_id            = aws_security_group.webapp.id
  ip_protocol                  = "tcp"
  from_port                    = var.webapp_port
  to_port                      = var.webapp_port
  referenced_security_group_id = aws_security_group.webapp.id
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_chroma" {
  security_group_id            = aws_security_group.chroma.id
  ip_protocol                  = "tcp"
  from_port                    = var.efs_nfs_port
  to_port                      = var.efs_nfs_port
  referenced_security_group_id = aws_security_group.chroma.id
}
