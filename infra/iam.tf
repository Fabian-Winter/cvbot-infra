data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "apigateway_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# Account-wide role API Gateway assumes to push access logs to CloudWatch;
# without it, stages with access_log_settings fail to be created.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "apigateway_cloudwatch" {
  name               = "${var.project}-apigateway-cloudwatch-role"
  assume_role_policy = data.aws_iam_policy_document.apigateway_assume.json
}

resource "aws_iam_role_policy_attachment" "apigateway_cloudwatch" {
  role       = aws_iam_role.apigateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# ---------------------------------------------------------------------------
# Runner role: read documents from S3, invoke Bedrock, read its own GitHub PAT.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "runner" {
  name               = "${var.project}-runner-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_ssm_parameter" "gh_pat" {
  name  = "/${var.project}/github-pat"
  type  = "SecureString"
  value = var.gh_pat
}

data "aws_iam_policy_document" "runner" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"]
  }

  # Same model allow list as the web application task: the runner embeds
  # documents and is used for command line smoke tests of the retriever.
  statement {
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = local.bedrock_model_arns
  }

  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.gh_pat.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"]
  }
}

resource "aws_iam_role_policy" "runner" {
  name   = "${var.project}-runner-policy"
  role   = aws_iam_role.runner.id
  policy = data.aws_iam_policy_document.runner.json
}

resource "aws_iam_role_policy_attachment" "runner_ssm" {
  role       = aws_iam_role.runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "runner" {
  name = "${var.project}-runner-profile"
  role = aws_iam_role.runner.name
}

# ---------------------------------------------------------------------------
# ECS task execution role (pull image, write logs)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# Web application task role: invoke the Bedrock models used by the retriever.
# ChromaDB is reached over the network, which is governed by security groups
# and needs no IAM permission.
# ---------------------------------------------------------------------------
locals {
  # Cross-region inference profiles route to the foundation model in any region
  # of the profile, so the region part of the model ARN stays a wildcard.
  bedrock_model_arns = concat(
    [for id in var.bedrock_foundation_model_ids : "arn:aws:bedrock:*::foundation-model/${id}"],
    [
      for id in var.bedrock_inference_profile_ids :
      "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${id}"
    ],
  )
}

resource "aws_iam_role" "webapp_task" {
  name               = "${var.project}-webapp-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "webapp_task" {
  statement {
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = local.bedrock_model_arns
  }
}

resource "aws_iam_role_policy" "webapp_task" {
  name   = "${var.project}-webapp-task-policy"
  role   = aws_iam_role.webapp_task.id
  policy = data.aws_iam_policy_document.webapp_task.json
}

# ---------------------------------------------------------------------------
# GitHub OIDC provider + deploy role assumed by the workflows (no static keys)
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "gha_deploy_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.gh_owner}@${var.gh_owner_id}/${var.project}-*"]
    }
  }
}

resource "aws_iam_role" "gha_deploy" {
  name               = "${var.project}-gha-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.gha_deploy_assume.json
}

data "aws_iam_policy_document" "gha_deploy" {
  # Power state of the runner: limited to the one instance the workflows toggle.
  statement {
    effect  = "Allow"
    actions = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.runner.id}"
    ]
  }

  # ec2:Describe* has no resource-level permissions and must stay on "*".
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances", "ec2:DescribeNetworkInterfaces"]
    resources = ["*"]
  }

  # Scaling the two services the workflows toggle, nothing else.
  statement {
    effect  = "Allow"
    actions = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [
      aws_ecs_service.chroma.id,
      aws_ecs_service.webapp.id,
    ]
  }

  # Task ARNs are not known in advance, so the cluster is pinned by condition.
  statement {
    effect    = "Allow"
    actions   = ["ecs:DescribeTasks", "ecs:ListTasks"]
    resources = ["*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.this.arn]
    }
  }

  # sts:GetCallerIdentity and ecr:GetAuthorizationToken are account wide calls
  # without resource-level permissions.
  statement {
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
    ]
    resources = [aws_ecr_repository.webapp.arn]
  }

  # A new revision has no ARN yet, so RegisterTaskDefinition cannot be scoped;
  # iam:PassRole below is what keeps it from running arbitrary roles.
  statement {
    effect    = "Allow"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }

  statement {
    effect  = "Allow"
    actions = ["ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.webapp_task.arn, aws_iam_role.ecs_task_execution.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "gha_deploy" {
  name   = "${var.project}-gha-deploy-policy"
  role   = aws_iam_role.gha_deploy.id
  policy = data.aws_iam_policy_document.gha_deploy.json
}
