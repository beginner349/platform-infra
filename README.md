# Infrastructure Project: Secure Keycloak Deployment on AWS

## Project Overview

This project automates the provisioning of a secure, production-ready infrastructure for **Keycloak**. 
The architecture includes a **VPC** with public and private subnets, an **Application Load Balancer (ALB)** handling HTTPS traffic with an Amazon-issued certificate, and **ECS Fargate**.
Data is persisted in an **Amazon Aurora PostgreSQL Serverless v2** cluster, with credentials securely managed by **AWS Secrets Manager**. 
The deployment is fully orchestrated through a GitLab CI/CD pipeline using **OIDC** for passwordless authentication to AWS

## Requirements

To manage this infrastructure, the following versions are required:

| Requirement   | Version       |
|---------------|---------------|
| Terraform     | `~> 1.14.7`   |
| AWS Provider  | `~> 6.28`     |

## Providers

The following providers are utilized within this module:

| Name    | Version       |
|---------|---------------|
| aws     | `~> 6.28`     |

## Inputs (Variables)

The configuration uses a mix of variables and localized constants.

| Name            | Description                                             | Type      | Default     | Required    |
|-----------------|---------------------------------------------------------|-----------|-------------|-------------|
| `AWS_ROLE_NAME` | Automatically populated by GitLab for OIDC role lookup  | `string`  | no          | **Yes**     |


Note: Key configuration values such as the region (`ap-southeast-1`) and VPC CIDR (`10.0.0.0/16`) are currently defined within locals in the `main.tf` file

## Outputs

These outputs provide essential information for post-deployment steps and verification:

| Name                        | Description                                                      |
|-----------------------------|------------------------------------------------------------------|
| `alb_dns`                   | The DNS name of the Application Load Balancer                    |
| `aurora_cluster_endpoint`   | The writer endpoint for the Aurora PostgreSQL cluster            |
| `aurora_cluster_port`       | The connection port for the Aurora cluster                       |
| `rds_username`              | The master username for the database                             |
| `aurora_secret_arn`         | The ARN of the Secrets Manager secret containing DB credentials  |

## Resources

### Providers
* **AWS (hashicorp/aws)**: Used for all infrastructure provisioning
* **HTTP**: Used for the GitLab-managed Terraform state backend

### Core Resources
* **Compute: AWS ECS Fargate** runs the Keycloak container, ensuring no EC2 management is required
* **Database: Amazon Aurora Serverless v2** (PostgreSQL) with automated password management in **AWS Secrets Manager**
* **Networking**: A custom **VPC** (via module) with public, private, and database subnets
* **Load Balancing: Application Load Balancer (ALB)** handles HTTPS traffic and redirects HTTP to HTTPS
* **Kubernetes: Amazon EKS** cluster configured with API authentication and auto-node roles
* **DNS: Route 53** alias record mapping `auth.beginner349.com` to the ALB
* **Security**: IAM Roles for EC2 and EKS access, along with specific **Security Groups** for the ALB, ECS, and Aurora

## Usage Examples

### GitLab CI/CD Pipeline

Standard Terraform commands can be used for local development, though the project is designed for GitLab CI/CD. The pipeline includes the following stages:
1. **Validate**: Checks syntax and formatting
2. **Plan**: Generates an execution plan artifact
3. **Deploy**: Applies the Terraform plan to AWS
5. **Cleanup**: A manual stage to destroy the infrastructure
