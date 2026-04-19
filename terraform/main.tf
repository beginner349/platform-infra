provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Security Group for ALB (Allow HTTP)
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = module.vpc.vpc_id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "allow_tcp_traffic_ipv4" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_alb" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports

  tags = local.tags
}

# Security Group for EC2 (Allow traffic from ALB and SSH)
resource "aws_security_group" "ec2_sg" {
  name   = "ec2-sg"
  vpc_id = module.vpc.vpc_id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "allow_tcp_traffic_ipv4_from_alb" {
  security_group_id            = aws_security_group.ec2_sg.id
  from_port                    = 80
  ip_protocol                  = "tcp"
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb_sg.id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_traffic_ipv4" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_ec2" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports

  tags = local.tags
}

data "aws_ssm_parameter" "al2023_latest" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# 1. Create an IAM Role for the EC2 Instance
resource "aws_iam_role" "ec2_secrets_role" {
  name = "ec2-secrets-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# 2. Grant permission to read the specific Aurora Secret
resource "aws_iam_policy" "ec2_secrets_policy" {
  name = "ec2-secrets-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "secretsmanager:GetSecretValue"
      Effect = "Allow"
      # This dynamically references the secret created by the Aurora module
      Resource = aws_rds_cluster.aurora_cluster.master_user_secret[0].secret_arn
    }]
  })
}

# 3. Attach the policy to the role
resource "aws_iam_role_policy_attachment" "ec2_secrets_attach" {
  role       = aws_iam_role.ec2_secrets_role.name
  policy_arn = aws_iam_policy.ec2_secrets_policy.arn
}

# 4. Create the Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-profile"
  role = aws_iam_role.ec2_secrets_role.name
}

resource "aws_instance" "web_server" {
  ami                    = data.aws_ssm_parameter.al2023_latest.value
  instance_type          = "m7i.large"
  key_name               = "ec2-key-pair"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = module.vpc.public_subnets[0]

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name # ADD THIS LINE

  tags = local.tags
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
  name     = "main-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}

# Listener
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Attachment
resource "aws_lb_target_group_attachment" "attachment" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web_server.id
  port             = 80
}

locals {
  region = "ap-southeast-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# Security Group for Aurora Postgres (Allow inbound traffic strictly from the EC2 SG)
resource "aws_security_group" "aurora_sg" {
  name   = "aurora-postgres-sg"
  vpc_id = module.vpc.vpc_id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "allow_tcp_traffic_from_ec2" {
  security_group_id            = aws_security_group.aurora_sg.id
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.ec2_sg.id

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

resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier = "dev-aurora-postgres-cluster"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "17.7"
  database_name      = "keycloak"
  master_username    = "postgres"

  # The magic flag for Secrets Manager integration!
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids = [aws_security_group.aurora_sg.id]

  # CRITICAL for learning: Allows `terraform destroy` to work cleanly without
  # hanging to take a final snapshot of the database.
  skip_final_snapshot = true

  # Aurora Serverless v2 Scaling configuration
  serverlessv2_scaling_configuration {
    min_capacity = 0.5 # Minimum Aurora Capacity Units (ACUs)
    max_capacity = 1.0 # Maximum ACUs (keeps costs completely capped for learning)
  }

  tags = local.tags
}

# ------------------------------------------------------------------------------
# Aurora Cluster Instance (Serverless v2)
# ------------------------------------------------------------------------------
resource "aws_rds_cluster_instance" "aurora_instances" {
  count              = 1 # Just 1 instance is needed for testing/learning
  identifier         = "dev-aurora-instance-${count.index}"
  cluster_identifier = aws_rds_cluster.aurora_cluster.id
  engine             = aws_rds_cluster.aurora_cluster.engine
  engine_version     = aws_rds_cluster.aurora_cluster.engine_version

  # "db.serverless" maps the instance to the Serverless v2 scaling config above
  instance_class = "db.serverless"

  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.aurora_subnet_group.name

  tags = local.tags
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

/*
resource "aws_eks_cluster" "dev-auto-cluster" {
  name    = "dev-auto-cluster"
  version = "1.35"

  bootstrap_self_managed_addons = false

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
*/