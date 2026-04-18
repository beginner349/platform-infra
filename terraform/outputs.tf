/*
output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.dev-auto-cluster.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = aws_eks_cluster.dev-auto-cluster.vpc_config[0].cluster_security_group_id
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = aws_eks_cluster.dev-auto-cluster.id
}
*/

output "alb_dns" {
  value = aws_lb.main_alb.dns_name
}

output "instance_public_ip" {
  value = aws_instance.web_server.public_ip
}

output "aurora_cluster_endpoint" {
  description = "The writer endpoint for the Aurora cluster"
  value       = aws_rds_cluster.aurora_cluster.endpoint
}

output "aurora_cluster_port" {
  description = "The port for the Aurora cluster"
  value       = aws_rds_cluster.aurora_cluster.port
}

output "aurora_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the DB credentials"
  value       = aws_rds_cluster.aurora_cluster.master_user_secret[0].secret_arn
}
