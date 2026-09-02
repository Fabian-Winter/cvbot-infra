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

# ChromaDB is only reachable from the runner, never from the public internet.
resource "aws_vpc_security_group_ingress_rule" "chroma_from_runner" {
  security_group_id            = aws_security_group.chroma.id
  ip_protocol                  = "tcp"
  from_port                    = var.chroma_port
  to_port                      = var.chroma_port
  referenced_security_group_id = aws_security_group.runner.id
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_chroma" {
  security_group_id            = aws_security_group.chroma.id
  ip_protocol                  = "tcp"
  from_port                    = var.efs_nfs_port
  to_port                      = var.efs_nfs_port
  referenced_security_group_id = aws_security_group.chroma.id
}
