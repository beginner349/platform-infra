output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.my-eks-cluster.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = aws_eks_cluster.my-eks-cluster.vpc_config[0].cluster_security_group_id
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = aws_eks_cluster.my-eks-cluster.id
}

/*
output "alb_dns" {
  value = aws_lb.main_alb.dns_name
}

output "aurora_cluster_endpoint" {
  description = "The writer endpoint for the Aurora cluster"
  value       = aws_rds_cluster.aurora_cluster.endpoint
}

output "aurora_cluster_port" {
  description = "The port for the Aurora cluster"
  value       = aws_rds_cluster.aurora_cluster.port
}

# Ensure your RDS username/password are accessible, 
# ideally pulled from AWS Secrets Manager or passed as variables.
output "rds_username" {
  value = aws_rds_cluster.aurora_cluster.master_username
}

output "aurora_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the DB credentials"
  value       = aws_rds_cluster.aurora_cluster.master_user_secret[0].secret_arn
}
*/