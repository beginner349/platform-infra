
### ------------------------------------------------------------------------------
### 1. DATA SOURCES
### ------------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Locates the SSL certificate for HTTPS termination on the ALB
data "aws_acm_certificate" "wildcard" {
  domain   = "*.${var.domain_name}"
  statuses = ["ISSUED"]
  types    = ["AMAZON_ISSUED"]
}

# Fetches the public DNS zone for record creation
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

data "aws_caller_identity" "current" {}

# commented out
/*
### ------------------------------------------------------------------------------
### 2. SECURITY GROUPS (NETWORK FIREWALLS)
### ------------------------------------------------------------------------------

# Public-facing SG for the Load Balancer
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = module.vpc.vpc_id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_traffic_ipv4" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "allow_https_traffic_ipv4" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_alb" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports

  tags = local.tags
}

# Security Group for ECS (Allow traffic from ALB)
resource "aws_security_group" "ecs_sg" {
  name   = "ecs-tasks-sg"
  vpc_id = module.vpc.vpc_id

  tags = local.tags
}

# Allow application traffic
resource "aws_vpc_security_group_ingress_rule" "allow_8080" {
  security_group_id            = aws_security_group.ecs_sg.id
  from_port                    = 8080
  ip_protocol                  = "tcp"
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.alb_sg.id

  tags = local.tags
}

# Allow health check traffic on the management port
resource "aws_vpc_security_group_ingress_rule" "allow_9000_health" {
  security_group_id            = aws_security_group.ecs_sg.id
  from_port                    = 9000
  to_port                      = 9000
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb_sg.id
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_ecs" {
  security_group_id = aws_security_group.ecs_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports

  tags = local.tags
}

### ------------------------------------------------------------------------------
### 3. IDENTITY AND ACCESS MANAGEMENT (IAM)
### ------------------------------------------------------------------------------

# Grants the ECS instance an identity to interact with AWS services
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Specific permission for Keycloak to retrieve its DB password securely from Secrets Manager
resource "aws_iam_policy" "ecs_secrets_policy" {
  name = "ecs-secrets-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "secretsmanager:GetSecretValue"
      Effect = "Allow"
      # This dynamically references the secret created by the Aurora module
      Resource = aws_secretsmanager_secret.keycloak_db.arn
    }]
  })
}

# Attach the standard Amazon ECS Execution Role policy
resource "aws_iam_role_policy_attachment" "ecs_execution_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_secrets_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_secrets_policy.arn
}

### ------------------------------------------------------------------------------
### 5. COMPUTE AND NETWORKING
### ------------------------------------------------------------------------------

resource "aws_ecs_cluster" "keycloak_ecs_cluster" {
  name = "keycloak-ecs-cluster"
  tags = local.tags
}

resource "aws_ecs_task_definition" "keycloak_realm_import" {
  family                   = "keycloak-realm-import"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "keycloak-import"
    image     = "${var.AWS_ECR}/beginner349/keycloak:${var.keycloak_image_tag}"
    essential = true

    environment = [
      { name = "KC_DB", value = "postgres" },
      { name = "KC_DB_URL", value = "jdbc:postgresql://${aws_rds_cluster.aurora_cluster.endpoint}:5432/keycloak" },
      { name = "KC_DB_USERNAME", value = "postgres" }
    ]

    # Securely inject the password from Secrets Manager [6]
    secrets = [{
      name      = "KC_DB_PASSWORD"
      valueFrom = "${aws_secretsmanager_secret.keycloak_db.arn}:password::"
    }]
    command = ["import", "--file", "/opt/keycloak/data/import/realm.json"]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.keycloak_import.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "keycloak-realm-import"
      }
    }
  }])
}

resource "aws_cloudwatch_log_group" "keycloak_import" {
  name = "/ecs/keycloak-realm-import"
  tags = local.tags
}

resource "aws_ecs_task_definition" "keycloak_task_definition" {
  family                   = "keycloak-task-definition"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "keycloak"
    image     = "${var.AWS_ECR}/beginner349/keycloak:${var.keycloak_image_tag}"
    essential = true
    portMappings = [
      { containerPort = 8080, hostPort = 8080 }, # Application
      { containerPort = 9000, hostPort = 9000 }  # Management (Health)
    ]
    environment = [
      { name = "KC_DB", value = "postgres" },
      { name = "KC_DB_URL", value = "jdbc:postgresql://${aws_rds_cluster.aurora_cluster.endpoint}:5432/keycloak" },
      { name = "KC_DB_USERNAME", value = "postgres" },
      { name = "KC_HOSTNAME", value = "https://auth.${var.domain_name}" },
      { name = "KC_PROXY_HEADERS", value = "xforwarded" },
      { name = "KC_HTTP_ENABLED", value = "true" },
      { name = "KC_BOOTSTRAP_ADMIN_USERNAME", value = "admin" },
      { name = "KC_BOOTSTRAP_ADMIN_PASSWORD", value = "password" },
      { name = "KC_HEALTH_ENABLED", value = "true" }
    ]
    # Securely inject the password from Secrets Manager [6]
    secrets = [{
      name      = "KC_DB_PASSWORD"
      valueFrom = "${aws_secretsmanager_secret.keycloak_db.arn}:password::"
    }]
    command = ["start"]
  }])
}

resource "aws_ecs_service" "keycloak_ecs_service" {
  name            = "keycloak-ecs-service"
  cluster         = aws_ecs_cluster.keycloak_ecs_cluster.id
  task_definition = aws_ecs_task_definition.keycloak_task_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "keycloak"
    container_port   = 8080
  }
}

# Application Load Balancer
resource "aws_lb" "main_alb" {
  name               = "main-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets
}

# Target Group
resource "aws_lb_target_group" "tg" {
  name        = "main-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    port = "9000"         # Explicitly use the management port
    path = "/health/live" # Default health path
  }
}

# Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.wildcard.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Points the custom domain to the ALB via an Alias record
resource "aws_route53_record" "alias_record_alb" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "auth.${var.domain_name}" # Replace with your subdomain
  type    = "A"

  alias {
    name                   = aws_lb.main_alb.dns_name
    zone_id                = aws_lb.main_alb.zone_id
    evaluate_target_health = true
  }
}
*/

### ------------------------------------------------------------------------------
### 4. DATABASE (AURORA SERVERLESS V2)
### ------------------------------------------------------------------------------

# Security Group for Aurora Postgres (Allow inbound traffic strictly from the ECS SG)
resource "aws_security_group" "aurora_sg" {
  name   = "aurora-postgres-sg"
  vpc_id = module.vpc.vpc_id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "allow_tcp_traffic_from_ecs" {
  security_group_id            = aws_security_group.aurora_sg.id
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  referenced_security_group_id = aws_eks_cluster.my_eks_cluster.vpc_config[0].cluster_security_group_id

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_aurora" {
  security_group_id = aws_security_group.aurora_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports

  tags = local.tags
}

resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = "aurora-db-subnet-group"
  subnet_ids = module.vpc.database_subnets # Ensure DB is in database subnets
  tags       = local.tags
}

resource "random_password" "password" {
  length           = 32
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "keycloak_db" {
  name                    = "keycloak/db-credentials"
  recovery_window_in_days = 0 # local dev: delete immediately on destroy so the name frees up
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "keycloak_db" {
  secret_id = aws_secretsmanager_secret.keycloak_db.id
  secret_string = jsonencode({
    username = aws_rds_cluster.aurora_cluster.master_username
    password = random_password.password.result
  })
}

resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier = "keycloak-db"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "18.3"
  database_name      = "keycloak"
  master_username    = "postgres"

  master_password_wo         = random_password.password.result
  master_password_wo_version = 1

  db_subnet_group_name   = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids = [aws_security_group.aurora_sg.id]

  # Allows `terraform destroy` to work cleanly without hanging to take a final snapshot of the database.
  skip_final_snapshot = true

  # Aurora Serverless v2 Scaling configuration
  serverlessv2_scaling_configuration {
    min_capacity = 1
    max_capacity = 4
  }

  tags = local.tags
}

resource "aws_rds_cluster_instance" "aurora_instances" {
  count              = 2
  identifier         = "aurora-instance-${count.index}"
  cluster_identifier = aws_rds_cluster.aurora_cluster.id
  engine             = aws_rds_cluster.aurora_cluster.engine
  engine_version     = aws_rds_cluster.aurora_cluster.engine_version

  # "db.serverless" maps the instance to the Serverless v2 scaling config above
  instance_class = "db.serverless"

  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.aurora_subnet_group.name

  tags = local.tags
}

### ------------------------------------------------------------------------------
### 6. LOCALS AND NETWORKING MODULE
### ------------------------------------------------------------------------------

locals {
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  oidc_url = replace(aws_iam_openid_connect_provider.eks_oidc_provider.url, "https://", "")

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }
}

module "vpc" {
  # refer to https://github.com/terraform-aws-modules/terraform-aws-vpc/blob/master/variables.tf for the available paramters in the module

  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = "custom-vpc"

  cidr = local.vpc_cidr
  azs  = local.azs

  private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k + 8)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

resource "aws_eks_cluster" "my_eks_cluster" {
  name    = "my-eks-cluster"
  version = "1.35"

  bootstrap_self_managed_addons = false

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true

    subnet_ids = module.vpc.private_subnets
  }

  compute_config {
    enabled       = true
    node_pools    = ["general-purpose"]
    node_role_arn = aws_iam_role.node.arn
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }

  storage_config {
    block_storage {
      enabled = true
    }
  }

  access_config {
    authentication_mode = "API"
  }

  # Ensure that IAM Role permissions are created before and deleted
  # after EKS Cluster handling. Otherwise, EKS will not be able to
  # properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSComputePolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSBlockStoragePolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSLoadBalancingPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSNetworkingPolicy,
    aws_iam_role_policy_attachment.cloudwatch_observability,
  ]

  tags = local.tags
}

data "aws_iam_policy_document" "cluster-trust-policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

resource "aws_iam_role" "cluster" {
  name               = "AmazonEKSAutoClusterRole"
  assume_role_policy = data.aws_iam_policy_document.cluster-trust-policy.json
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSComputePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSComputePolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSBlockStoragePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSLoadBalancingPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSNetworkingPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role" "node" {
  name = "AmazonEKSAutoNodeRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole"]
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodeMinimalPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryPullOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
  role       = aws_iam_role.node.name
}

data "tls_certificate" "eks_tls_cert" {
  url = aws_eks_cluster.my_eks_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url = aws_eks_cluster.my_eks_cluster.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.eks_tls_cert.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "eks_service_iam_role" {
  name = "eks-service-iam-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_oidc_provider.arn
        }
        Condition = {
          StringEquals = {
            "${local.oidc_url}:aud" = "sts.amazonaws.com"
            "${local.oidc_url}:sub" = "system:serviceaccount:beginner349-${var.environment}:beginner349-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "role_policy_attach" {
  role       = aws_iam_role.eks_service_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
}

resource "aws_iam_role" "eso_irsa" {
  name = "eso-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_oidc_provider.arn
        }
        Condition = {
          StringEquals = {
            "${local.oidc_url}:aud" = "sts.amazonaws.com"
            "${local.oidc_url}:sub" = "system:serviceaccount:external-secrets:external-secrets-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "eso_policy" {
  name = "eso-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Effect   = "Allow"
        Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.environment}/grafana-cloud/*"
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = aws_secretsmanager_secret.keycloak_db.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eso_policy_attachment" {
  role       = aws_iam_role.eso_irsa.name
  policy_arn = aws_iam_policy.eso_policy.arn
}

resource "aws_iam_role" "external_dns_irsa" {
  name = "external-dns-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_oidc_provider.arn
        }
        Condition = {
          StringEquals = {
            "${local.oidc_url}:aud" = "sts.amazonaws.com"
            "${local.oidc_url}:sub" = "system:serviceaccount:external-dns:external-dns-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "external_dns_policy" {
  name = "external-dns-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/${data.aws_route53_zone.main.zone_id}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResources"
        ]
        Resource = [
          "*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_dns_attach" {
  role       = aws_iam_role.external_dns_irsa.name
  policy_arn = aws_iam_policy.external_dns_policy.arn
}

# EKS Pod Identity role for the amazon-cloudwatch-observability add-on.
# On EKS Auto Mode, pods cannot use the node instance role, and the
# pod-identity agent is built into Auto Mode nodes (no extra add-on needed).
resource "aws_iam_role" "cloudwatch_observability" {
  name = "cloudwatch-observability-pod-identity"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = ["sts:AssumeRole", "sts:TagSession"]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_observability.name
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name  = aws_eks_cluster.my_eks_cluster.name
  addon_name    = "amazon-cloudwatch-observability"
  addon_version = "v6.3.0-eksbuild.1"

  # Both the CloudWatch agent and the Fluent Bit daemonset run under the
  # cloudwatch-agent service account in the amazon-cloudwatch namespace,
  # so this single association covers all of the add-on's pods.
  pod_identity_association {
    role_arn        = aws_iam_role.cloudwatch_observability.arn
    service_account = "cloudwatch-agent"
  }

  configuration_values = jsonencode({
    containerLogs = {
      enabled = true

      fluentBit = {
        config = {
          extraFiles = {
            # do not send application logs from the cluster
            "application-log.conf" = ""
          }
        }
      }
    }
  })

  tags = local.tags
}
