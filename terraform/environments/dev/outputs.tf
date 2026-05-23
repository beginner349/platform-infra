output "cluster_endpoint" {
  value = module.platform.cluster_endpoint
}

output "cluster_security_group_id" {
  value = module.platform.cluster_security_group_id
}

output "cluster_name" {
  value = module.platform.cluster_name
}

output "alb_dns" {
  value = module.platform.alb_dns
}

output "aurora_cluster_endpoint" {
  value = module.platform.aurora_cluster_endpoint
}

output "aurora_cluster_port" {
  value = module.platform.aurora_cluster_port
}

output "rds_username" {
  value = module.platform.rds_username
}

output "aurora_secret_arn" {
  value = module.platform.aurora_secret_arn
}