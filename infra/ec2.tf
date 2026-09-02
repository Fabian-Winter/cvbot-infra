locals {
  primary_subnet_id = data.aws_subnets.default.ids[0]
}

resource "aws_instance" "runner" {
  ami                    = data.aws_ssm_parameter.runner_ami.value
  instance_type          = var.ec2_instance_type
  subnet_id              = local.primary_subnet_id
  vpc_security_group_ids = [aws_security_group.runner.id]
  iam_instance_profile   = aws_iam_instance_profile.runner.name

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    aws_region     = var.aws_region
    gh_owner       = var.gh_owner
    gh_repo        = var.gh_repo
    ssm_pat_param  = aws_ssm_parameter.gh_pat.name
    runner_version = var.runner_version
    runner_label   = var.runner_label
  })

  tags = {
    Name = "${var.project}-gha-runner"
  }

  # Power state (start/stop) is controlled exclusively by the start-project
  # and run-pipeline workflows, not by Terraform.
  lifecycle {
    ignore_changes = [user_data]
  }
}
