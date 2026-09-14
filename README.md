# cvbot-infra
Terraform project for the CVBot RAG infrastructure

## Architecture

![CVBot infrastructure diagram](docs/infrastructure.png)

### Web application

The `cvbot-retriever` web application runs as a second Fargate service in the
existing ECS cluster.

```
Internet -- HTTPS --> API Gateway HTTP API ($default stage)
                        |
                        +-- VPC link --> Cloud Map "webapp" (SRV)
                                            |
                                            +-- webapp task --> chroma task
```

- **Public access** goes through an API Gateway HTTP API, which provides HTTPS
  on its default `execute-api` domain without owning a domain or managing
  certificates. Unlike a load balancer it has no hourly charge, so scaling the
  service to `desired_count = 0` leaves no idle cost.
- **Service discovery** via the Cloud Map namespace `cvbot.internal` gives both
  services stable DNS names despite changing Fargate task IPs. The web app
  registers an SRV record because API Gateway needs the port; ChromaDB
  registers an A record and is reached at `chroma.cvbot.internal`.
- **ChromaDB stays private.** Its security group has no public ingress rule;
  only the runner and the web application security groups may reach
  `chroma_port`. The web app itself only accepts traffic from the VPC link.
- **Scaling** follows the ChromaDB pattern: `desired_count` toggles between 0
  and 1 from the workflows, and Terraform ignores it. The service runs exactly
  one task, which is what the in-memory conversation store requires.
- **Images** are pushed to the `cvbot-webapp` ECR repository by the deploy
  workflow, which assumes the existing `gha_deploy` OIDC role.

## Security

- **Request throttling.** The API Gateway stage caps the total load through
  `webapp_throttle_rate_limit` and `webapp_throttle_burst_limit`, which bounds
  the Bedrock spend even if a single client misbehaves. The application adds a
  per-client limit on top (`webapp_rate_limit_per_minute`,
  `webapp_rate_limit_per_hour`), because the gateway cannot tell callers apart.
- **Log retention.** Both log groups (`/ecs/cvbot` and
  `/aws/apigateway/cvbot-webapp`) expire after `log_retention_days`, seven days
  by default, so nothing is stored indefinitely. The gateway access log format
  carries request metadata only, never a request body, and the application logs
  no conversation content.
- **No persistence of conversations.** Conversations live in the memory of the
  single task, bounded by `webapp_conversation_ttl_seconds` and
  `webapp_max_conversations`. No database, no volume, nothing to back up.
- **Least privilege IAM.** Each role carries only the actions it needs, on
  concrete ARNs wherever the AWS API supports it:
  - The web application task role may invoke exactly the configured Bedrock
    models and nothing else; ChromaDB is reached over the network, which needs
    no IAM permission at all.
  - The runner role is scoped to the documents bucket, its own SSM parameter
    and the same Bedrock model list.
  - The deploy role may start and stop the one runner instance, update the two
    ECS services and push to the one ECR repository. `iam:PassRole` is limited
    to the two task roles and to `ecs-tasks.amazonaws.com`, which is what keeps
    `ecs:RegisterTaskDefinition` from running arbitrary roles.
  - A few actions have no resource-level permissions in IAM and stay on `"*"`:
    `ec2:Describe*`, `ecs:RegisterTaskDefinition`, `ecr:GetAuthorizationToken`
    and `sts:GetCallerIdentity`. `ecs:ListTasks` and `ecs:DescribeTasks` are
    instead pinned to the cluster through an `ecs:cluster` condition.
- **Encryption.** The EFS file system, the ECR repository and both S3 buckets
  are encrypted at rest; EFS uses transit encryption, and public access is
  blocked on the buckets.
- **Deliberately out of scope.** No WAF in front of the API Gateway, no
  authentication, no KMS customer managed keys and no GuardDuty. This is a
  public showcase without confidential data.
