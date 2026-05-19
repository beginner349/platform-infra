# Infrastructure Project: Secure Keycloak Deployment on AWS

[![Terraform Deploy](https://github.com/beginner349/platform-infra/actions/workflows/terraform-deploy.yml/badge.svg)](https://github.com/beginner349/platform-infra/actions/workflows/terraform-deploy.yml)

## Project Overview

 ```mermaid
flowchart TD
  subgraph Internet
    User((User))
  end

  subgraph AWS_Cloud ["AWS Cloud (ap-southeast-1)"]
    route-53[Route 53: auth.beginner349.com]
    dynamodb[(AWS DynamoDB)]
    secrets[AWS Secrets Manager]
    acm[AWS Certificate Manager]
    s3[("S3 Backend (State Locking Enabled)")]    

    subgraph VPC ["Custom VPC (10.0.0.0/16)"]
        subgraph Public_Subnets ["Public Subnets"]
          subgraph keycloak-alb[Application Load Balancer: keycloak]
              P80[Port 80: HTTP]
              P443[Port 443: HTTPS]
          end 
          spring-boot-alb[Application Load Balancer: spring boot]
        end

        subgraph Private_Subnets ["Private Subnets"]
            subgraph EKS_Cluster ["Amazon EKS (Auto Mode)"]
                app[Spring Boot App: beginner349-app]
            end
            
            subgraph ECS_Fargate ["Amazon ECS Fargate"]
                keycloak[Keycloak Container]
            end
        end

        subgraph DB_Subnets ["Database Subnets"]
            aurora[(Aurora Serverless v2)]
        end
    end
  end

  subgraph CI_CD ["CI/CD Pipeline (GitOps)"]
      GHA[GitHub Actions]
      OIDC[OIDC Authentication]
      TF[Terraform]
  end

  %% Traffic Flow
  User --> route-53
  route-53 --> keycloak-alb
  P80 -- "301 Redirect" --> P443
  acm -- "SSL Certificate" --> P443
  P443 -- "Decrypted Traffic (SSL Termination)" --> keycloak    

  spring-boot-alb -- Port 80 --> app

  %% Infrastructure Management
  GHA --> TF
  TF -- "use_lockfile = true" --> s3
  TF --> OIDC
  OIDC -- "Deploy & Provision" --> AWS_Cloud

  %% Persistence
  app --> dynamodb
  keycloak --> aurora
  secrets o--o aurora
```

This project automates the provisioning of a secure, production-ready infrastructure for **Keycloak**. 
The architecture includes a **VPC** with public and private subnets, an **Application Load Balancer (ALB)** handling HTTPS traffic with an Amazon-issued certificate, and **ECS Fargate**.
Data is persisted in an **Amazon Aurora PostgreSQL Serverless v2** cluster, with credentials securely managed by **AWS Secrets Manager**. 
The deployment is fully orchestrated through **GitHub Actions** using **OIDC** for passwordless authentication to AWS, ensuring a secure and streamlined CI/CD process

## Requirements

To manage this infrastructure, the following versions are required:

| Requirement   | Version       |
|---------------|---------------|
| Terraform     | `~> 1.14.7`   |
| AWS Provider  | `~> 6.28`     |

## Backend Configuration

The Terraform state is stored securely using an **S3 backend** with **native state locking** enabled to prevent concurrent executions

* Bucket: terraform-state-bucket-<AWS_ACCOUNT_ID>-ap-southeast-1-an
* Region: ap-southeast-1
* State Locking: Enabled via use_lockfile = true

## Inputs (Variables)

The following variable is required for OIDC-based authentication within the GitHub Actions environment:

| Name            | Description                                                                                                  | Type      | Default | Required |
|-----------------|--------------------------------------------------------------------------------------------------------------|-----------|---------|---------|
| `DOMAIN_NAME  ` | The dmian name for keycloak service, injected via GitHub Actions environment variables (`vars.DOMAIN_NAME`)  | `string`  | no      | **Yes**  |
| `AWS_ROLE_NAME` | The name of the IAM Role for OIDC, injected via GitHub Actions environment variables (`vars.AWS_ROLE_NAME`)  | `string`  | no      | **Yes**  |

Note: Regional settings (ap-southeast-1) and VPC CIDR (10.0.0.0/16) are defined as constants within the `locals` block in `main.tf`

## Core Resources
* **Compute: AWS ECS Fargate** runs the Keycloak container, ensuring no EC2 management is required
* **Database: Amazon Aurora Serverless v2** (PostgreSQL) with automated password management in **AWS Secrets Manager**
* **Networking**: A custom **VPC** (via module) with public, private, and database subnets
* **Load Balancing: Application Load Balancer (ALB)** handles HTTPS traffic and redirects HTTP to HTTPS
* **Kubernetes: Amazon EKS** cluster configured with API authentication and auto-node roles
* **DNS: Route 53** alias record mapping `auth.beginner349.com` to the ALB
* **Security**: IAM Roles for EC2 and EKS access, along with specific **Security Groups** for the ALB, ECS, and Aurora

## CI/CD Workflows (GitHub Actions)

The infrastructure is managed through two primary GitHub workflows located in `.github/workflows/`:

1. Terraform Deploy
* Trigger: Automatically runs on a push to the `master` branch or can be triggered manually via `workflow_dispatch`
* Process:
- Terraform Plan: Generates and validates the execution plan
- Terraform Apply: Applies the changes to the production environment (requires OIDC `id-token` write permissions)

2. Terraform Destroy
* Trigger: Manual trigger only via `workflow_dispatch` to prevent accidental deconstruction
* Process: Executes a full `terraform destroy` to tear down all provisioned AWS resources

## Outputs

Once deployed, the following outputs are available for verification:

| Name                        | Description                                                      |
|-----------------------------|------------------------------------------------------------------|
| `alb_dns`                   | The DNS name of the Application Load Balancer                    |
| `aurora_cluster_endpoint`   | The writer endpoint for the Aurora PostgreSQL cluster            |
| `aurora_secret_arn`         | The ARN of the Secrets Manager secret containing DB credentials  |
| `cluster_name`              | The name of the provisioned EKS cluster                          |


## TODO
- [x] Setting Up OpenID Connect (OIDC) in AWS for GitHub Actions
- [x] Configuring an S3 Remote Backend for Terraform State and Locking
- [x] Creating Infrastructure as Code (IaC) for IAM Roles for Service Accounts (IRSA)
- [x] Create import files for Keycloak realms, users, and clients
- [ ] Enable logging and monitoring in the EKS cluster
- [ ] Implement TLS/SSL for the ingress with a custom domain using ExternalDNS and Route 53
