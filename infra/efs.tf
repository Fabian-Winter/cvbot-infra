resource "aws_efs_file_system" "chroma" {
  encrypted       = true
  throughput_mode = "bursting"

  tags = {
    Name = "${var.project}-chroma-efs"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_efs_mount_target" "chroma" {
  for_each = toset(data.aws_subnets.default.ids)

  file_system_id  = aws_efs_file_system.chroma.id
  subnet_id       = each.value
  security_groups = [aws_security_group.chroma.id]
}

resource "aws_efs_access_point" "chroma" {
  file_system_id = aws_efs_file_system.chroma.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = var.efs_access_point_path
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = {
    Name = "${var.project}-chroma-ap"
  }
}
