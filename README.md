# Infrastructure Project: Secure Keycloak Deployment on AWS

## Project Overview

This project automates the provisioning of a secure, production-ready infrastructure for **Keycloak**. 
The architecture includes a **VPC** with public and private subnets, an **Application Load Balancer (ALB)** handling HTTPS traffic with an Amazon-issued certificate, and an **EC2 instance** running Keycloak via Docker. 
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
| `ec2_public_ip`             | The public IP address of the Keycloak EC2 instance               |
| `aurora_cluster_endpoint`   | The writer endpoint for the Aurora PostgreSQL cluster            |
| `aurora_cluster_port`       | The connection port for the Aurora cluster                       |
| `rds_username`              | The master username for the database                             |
| `aurora_secret_arn`         | The ARN of the Secrets Manager secret containing DB credentials  |

## Resources

The following high-level resources are managed by this project:
* **Networking**: A custom **VPC** with public, private, and database subnets
* **Compute**: An **EC2 Instance** (m7i.large) running Amazon Linux 2023
* **Database**: An **Aurora PostgreSQL Serverless v2** cluster with auto-scaling (0.5 to 1.0 ACUs)
* **Load Balancing**: An **Application Load Balancer** with listeners for HTTP (redirect to HTTPS) and HTTPS
* **Security**: IAM Roles for EC2 and EKS access, along with specific **Security Groups** for the ALB, EC2, and Aurora
* **DNS**: A **Route 53** Alias record pointing your custom domain to the ALB

## Usage Examples

### Local Execution

To initialize and apply the configuration locally:
terraform init
terraform plan
terraform apply

### GitLab CI/CD Pipeline

The project is designed to run automatically in GitLab. The pipeline includes the following stages:
1. **Validate**: Checks syntax and formatting
2. **Plan**: Generates an execution plan artifact
3. **Deploy**: Applies the Terraform plan to AWS
4. **Ansible Deploy**: Executes the Ansible playbook to pull the Keycloak Docker image and connect it to the Aurora DB
5. **Cleanup**: A manual stage to destroy the infrastructure

### Keycloak Deployment via Ansible

The following command is used within the pipeline to deploy Keycloak:

```bash
ansible-playbook -i "$INSTANCE_IP," -u ec2-user deploy-keycloak.yml \
  --extra-vars "db_endpoint=$DB_ENDPOINT secret_arn=$SECRET_ARN"
```

This playbook installs Docker, fetches the DB password from Secrets Manager, and runs the Keycloak container
