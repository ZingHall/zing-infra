# ECS Service Module

A lightweight module for creating AWS ECS Fargate services. This module focuses solely on service creation and requires external cluster, ALB, target group, and IAM roles.

## Features

- ✅ Lightweight and focused on service creation only
- ✅ ECS Fargate service with task definition
- ✅ Security group management
- ✅ Fully configurable task resources (CPU/memory)
- ✅ Uses external IAM roles (managed by `ecs-role` module)
- ✅ Clean separation of concerns

## Philosophy

This module follows the "do one thing well" principle - it creates ECS services and nothing else. You provide the cluster, ALB, target group, and IAM roles separately, giving you maximum flexibility to:

- **Share clusters** across multiple services
- **Share ALBs** across multiple services
- **Share IAM roles** or create service-specific roles
- **Mix and match** different infrastructure patterns
- **Scale** cluster and ALB independently

## Required External Resources

This module requires these external resources:

1. **ECS Cluster** - Created with `ecs-cluster` module
2. **ALB** - Created with `https-alb` module
3. **Target Group** - Created with `https-alb` module
4. **IAM Roles** - Created with `ecs-role` module (execution + task roles)

## Usage

### Complete Example

```hcl
# 1. Create ECS Cluster
module "cluster" {
  source = "../../../modules/aws/ecs-cluster"
  
  name                       = "prod-services"
  container_insights_enabled = true
  
  tags = var.tags
}

# 2. Create ALB with Target Groups
module "alb" {
  source = "../../../modules/aws/https-alb"
  
  name            = "prod"
  vpc_id          = var.vpc_id
  subnet_ids      = var.public_subnet_ids
  certificate_arn = var.cert_arn
  
  services = [
    {
      name          = "api"
      port          = 8080
      host_headers  = ["api.example.com"]
      priority      = 100
      health_check_path = "/api/health"
    },
    {
      name          = "web"
      port          = 3000
      host_headers  = ["www.example.com"]
      priority      = 101
      health_check_path = "/health"
    }
  ]
  
  tags = var.tags
}

# 3. Create IAM Roles for API service
module "api_roles" {
  source = "../../../modules/aws/ecs-role"
  
  name = "api"
  
  enable_secrets_access = true
  secrets_arns = ["arn:aws:secretsmanager:*:*:secret:api-*"]
  
  task_role_policies = {
    s3-access = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "arn:aws:s3:::my-bucket/*"
      }]
    })
  }
  
  tags = var.tags
}

# 4. Create ECS Service for API
module "api" {
  source = "../../../modules/aws/ecs-service"
  
  name = "api"
  
  # Required external resources
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["api"]
  execution_role_arn    = module.api_roles.execution_role_arn
  task_role_arn         = module.api_roles.task_role_arn
  
  # Network configuration
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  
  # Service configuration
  container_port = 8080
  desired_count  = 3
  
  task_cpu    = 512
  task_memory = 1024
  
  tags = var.tags
}

# 5. Create IAM Roles for Web service
module "web_roles" {
  source = "../../../modules/aws/ecs-role"
  
  name = "web"
  
  tags = var.tags
}

# 6. Create ECS Service for Web
module "web" {
  source = "../../../modules/aws/ecs-service"
  
  name = "web"
  
  # Use same cluster and ALB, different roles
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["web"]
  execution_role_arn    = module.web_roles.execution_role_arn
  task_role_arn         = module.web_roles.task_role_arn
  
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  
  container_port = 3000
  desired_count  = 2
  
  tags = var.tags
}
```

### Minimal Example

```hcl
module "my_service" {
  source = "../../../modules/aws/ecs-service"
  
  name = "my-app"
  
  # Required: External resources
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["my-app"]
  execution_role_arn    = module.app_roles.execution_role_arn
  task_role_arn         = module.app_roles.task_role_arn
  
  # Required: Network
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  
  # Optional: Service configuration
  container_port = 3000
  desired_count  = 2
  
  tags = var.tags
}
```

## Inputs

### Required Variables

| Name | Description | Type |
|------|-------------|------|
| name | Service name | string |
| cluster_id | ECS cluster ID | string |
| alb_security_group_id | ALB security group ID | string |
| target_group_arn | Target group ARN | string |
| execution_role_arn | Task execution role ARN (from ecs-role module) | string |
| task_role_arn | Task role ARN (from ecs-role module) | string |
| vpc_id | VPC ID | string |
| private_subnet_ids | Private subnet IDs for ECS tasks | list(string) |

### Optional Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| desired_count | Desired task count | number | 1 |
| container_name | Container name | string | "app" |
| container_port | Container port | number | 3000 |
| task_cpu | Task CPU units | number | 256 |
| task_memory | Task memory (MB) | number | 512 |
| assign_public_ip | Assign public IP to tasks | bool | false |
| tags | Resource tags | map(string) | {} |

## Outputs

| Name | Description |
|------|-------------|
| ecs_service_id | ECS service ID |
| ecs_service_name | ECS service name |
| ecs_service_sg_id | ECS service security group ID |
| ecs_service_sg_arn | ECS service security group ARN |
| task_definition_arn | Task definition ARN |

## Architecture

```
External Resources (You Create):
├─ ECS Cluster (ecs-cluster module)
├─ ALB + Target Groups (https-alb module)
└─ IAM Roles (ecs-role module)
    ├─ Execution Role
    └─ Task Role

This Module Creates:
├─ ECS Service
├─ Task Definition
└─ Security Group (ECS tasks)
```

## Benefits

### 1. Maximum Flexibility
- Share clusters across any number of services
- Share ALBs across any number of services
- Share IAM roles or create service-specific roles
- Independent lifecycle management

### 2. Cost Optimization
```
Before (3 services with embedded resources):
  3 Clusters + 3 ALBs = $48/month

After (3 services with shared resources):
  1 Cluster + 1 ALB = $16/month
  
Savings: $32/month (67% reduction)
```

### 3. Clear Separation of Concerns
- Cluster management (ecs-cluster)
- Load balancer management (https-alb)
- IAM role management (ecs-role)
- Service management (ecs-service) ← This module
- Easy to understand and maintain

### 4. Better for Microservices
- Deploy/destroy services independently
- Scale services independently
- Update services without affecting others
- Centralized IAM role management

## Security

### Security Group Configuration

The module creates a security group for ECS tasks that:
- **Ingress**: Allows traffic from ALB on the specified container port
- **Egress**: Allows all outbound traffic

### IAM Roles

This module **requires** IAM roles created by the `ecs-role` module:
- **Execution Role**: Used by ECS to pull images and write logs
- **Task Role**: Used by your application code for AWS API access

### Best Practices

1. **Use Private Subnets**: Always deploy ECS tasks in private subnets
2. **Use ecs-role Module**: Create IAM roles with `ecs-role` module for consistent permissions
3. **Least Privilege**: Grant only necessary permissions via task role
4. **Secrets Management**: Use AWS Secrets Manager (configured in ecs-role)
5. **Network Isolation**: Use security groups to control traffic

## Task Definition

The module creates a basic task definition with:
- Fargate launch type
- awsvpc network mode
- Configurable CPU and memory
- Container port mapping
- External IAM roles

**Note**: The task definition created here is a placeholder. Your CI/CD pipeline should update it with the actual container image and environment variables.

## CI/CD Integration

### Typical Workflow

1. **Terraform** creates infrastructure:
   - Cluster (ecs-cluster)
   - ALB + Target Groups (https-alb)
   - IAM Roles (ecs-role) ← Exports role ARNs
   - ECS Service (ecs-service) ← Uses role ARNs

2. **CI/CD** manages application:
   - Builds Docker image
   - Pushes to ECR
   - Registers new task definition with same role ARNs
   - Updates ECS service

3. **ECS** runs containers using the IAM roles

This separates infrastructure (Terraform) from application deployment (CI/CD)!

## Examples

### Example 1: API Service with S3 Access

```hcl
# Create IAM roles with S3 permissions
module "api_roles" {
  source = "../../../modules/aws/ecs-role"
  
  name = "api"
  
  enable_secrets_access = true
  secrets_arns = ["arn:aws:secretsmanager:*:*:secret:api-*"]
  
  task_role_policies = {
    s3-access = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::my-bucket/*"
      }]
    })
  }
}

# Create ECS service
module "api_service" {
  source = "../../../modules/aws/ecs-service"
  
  name = "api"
  
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["api"]
  execution_role_arn    = module.api_roles.execution_role_arn
  task_role_arn         = module.api_roles.task_role_arn
  
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  
  container_port = 8080
  desired_count  = 5
  task_cpu       = 1024
  task_memory    = 2048
  
  tags = {
    Environment = "production"
    Team        = "backend"
  }
}
```

### Example 2: Multi-Environment

```hcl
# Dev environment
module "dev_cluster" {
  source = "../../../modules/aws/ecs-cluster"
  name   = "dev-services"
}

module "dev_alb" {
  source = "../../../modules/aws/https-alb"
  name   = "dev"
  # ... config
}

module "dev_roles" {
  source = "../../../modules/aws/ecs-role"
  name   = "dev-api"
}

module "dev_api" {
  source = "../../../modules/aws/ecs-service"
  name   = "api"
  
  cluster_id            = module.dev_cluster.cluster_id
  alb_security_group_id = module.dev_alb.alb_security_group_id
  target_group_arn      = module.dev_alb.target_group_arns["api"]
  execution_role_arn    = module.dev_roles.execution_role_arn
  task_role_arn         = module.dev_roles.task_role_arn
  
  # ... rest of config
}

# Prod environment (separate cluster, ALB, and roles)
module "prod_cluster" {
  source = "../../../modules/aws/ecs-cluster"
  name   = "prod-services"
  container_insights_enabled = true
}

module "prod_alb" {
  source = "../../../modules/aws/https-alb"
  name   = "prod"
  # ... config
}

module "prod_roles" {
  source = "../../../modules/aws/ecs-role"
  name   = "prod-api"
  enable_secrets_access = true
}

module "prod_api" {
  source = "../../../modules/aws/ecs-service"
  name   = "api"
  
  cluster_id            = module.prod_cluster.cluster_id
  alb_security_group_id = module.prod_alb.alb_security_group_id
  target_group_arn      = module.prod_alb.target_group_arns["api"]
  execution_role_arn    = module.prod_roles.execution_role_arn
  task_role_arn         = module.prod_roles.task_role_arn
  
  # ... rest of config
}
```

### Example 3: Shared IAM Roles

If multiple services need the same permissions, you can share roles:

```hcl
# Create shared IAM roles for read-only services
module "readonly_roles" {
  source = "../../../modules/aws/ecs-role"
  
  name = "shared-readonly"
  
  task_role_policies = {
    s3-readonly = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
      }]
    })
  }
}

# Multiple services use the same roles
module "service_a" {
  source = "../../../modules/aws/ecs-service"
  name   = "service-a"
  
  execution_role_arn = module.readonly_roles.execution_role_arn
  task_role_arn      = module.readonly_roles.task_role_arn
  # ... other config
}

module "service_b" {
  source = "../../../modules/aws/ecs-service"
  name   = "service-b"
  
  execution_role_arn = module.readonly_roles.execution_role_arn
  task_role_arn      = module.readonly_roles.task_role_arn
  # ... other config
}
```

## Related Modules

- **`ecs-cluster`** - Create ECS clusters
- **`https-alb`** - Create ALBs with target groups
- **`ecs-role`** - Create IAM roles for ECS tasks ⭐
- **`ecs-cron-job`** - Create scheduled ECS tasks

## Troubleshooting

### Service Won't Start

**Check**: Security group rules
```bash
aws ec2 describe-security-groups --group-ids <sg-id>
```

**Verify**: ALB can reach ECS tasks on the specified port

### Tasks Failing Health Checks

**Check**: Target group health check configuration
```bash
aws elbv2 describe-target-health --target-group-arn <arn>
```

**Verify**: Application is listening on the correct port

### Can't Pull Docker Image

**Check**: Execution role has ECR permissions
```bash
aws iam get-role-policy --role-name <execution-role> --policy-name <policy>
```

The `ecs-role` module includes ECR permissions by default.

### Permission Denied Errors

**Check**: Task role has required permissions
```bash
aws iam list-role-policies --role-name <task-role>
```

Update the `task_role_policies` in the `ecs-role` module.

## FAQ

**Q: Why separate IAM roles into another module?**  
A: This allows you to:
- Share roles across multiple services
- Manage permissions centrally
- Update permissions without recreating services
- Follow the single responsibility principle

**Q: Can I use this without an ALB?**  
A: Currently, this module expects a target group. For worker services without load balancers, you'll need to modify the module or create a dummy target group.

**Q: How do I deploy new versions?**  
A: Update your container image via CI/CD. The service uses `ignore_changes` on task_definition to allow external updates.

**Q: Can I use EC2 launch type?**  
A: This module is designed for Fargate. For EC2, you'd need to fork and modify.

**Q: How many services can share a cluster and roles?**  
A: There's no practical limit. Share freely based on your permission requirements!

**Q: Do I need separate roles for each service?**  
A: Only if they need different permissions. Services with similar permissions can share roles.

## Migration from Old Version

If you were using an older version that created IAM roles internally:

### Before
```hcl
module "service" {
  source = "../../../modules/aws/ecs-service"
  name   = "api"
  # ... no role parameters
}

output "execution_role" {
  value = module.service.execution_role_arn
}
```

### After
```hcl
# Create roles first
module "api_roles" {
  source = "../../../modules/aws/ecs-role"
  name   = "api"
}

# Pass roles to service
module "service" {
  source = "../../../modules/aws/ecs-service"
  name   = "api"
  
  execution_role_arn = module.api_roles.execution_role_arn
  task_role_arn      = module.api_roles.task_role_arn
  # ... other config
}

# Get roles from ecs-role module
output "execution_role" {
  value = module.api_roles.execution_role_arn
}
```

## Contributing

This module is designed to be simple and focused. If you need more features, consider:
1. Forking and extending
2. Creating wrapper modules
3. Managing additional resources separately

## License

This module is provided as-is for use in your Terraform projects.
