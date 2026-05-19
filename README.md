# Cloud-Native Platform: EKS + Keycloak + Full-Stack Observability

[![Terraform Deploy](https://github.com/beginner349/platform-infra/actions/workflows/terraform-deploy.yml/badge.svg)](https://github.com/beginner349/platform-infra/actions/workflows/terraform-deploy.yml)
![Terraform](https://img.shields.io/badge/Terraform-1.14-7B42BC?logo=terraform)
![AWS](https://img.shields.io/badge/AWS-EKS_Auto_Mode-FF9900?logo=amazonaws)
![Spring Boot](https://img.shields.io/badge/Spring_Boot-4.0-6DB33F?logo=springboot)
![Grafana](https://img.shields.io/badge/Grafana-Cloud-F46800?logo=grafana)

A production-grade AWS platform built with Terraform, running a Spring Boot application on EKS alongside Keycloak on ECS Fargate, with end-to-end OpenTelemetry observability via Grafana Cloud and zero-credential secret management through the External Secrets Operator.

---

## Repository Map

This project is split across three purpose-built repositories that work together as a complete platform:

| Repository                                                        | Role                            | Stack                                                                                               |
|-------------------------------------------------------------------|---------------------------------|-----------------------------------------------------------------------------------------------------|
| **platform-infra** (this repo)                                    | AWS infrastructure provisioning | Terraform, EKS Auto Mode, ECS Fargate, Aurora Serverless v2, DynamoDB, VPC, ALB, Route53, ACM, IRSA |
| [beginner349-app](https://github.com/beginner349/beginner349-app) | Spring Boot application + CI/CD | Spring Boot 4.0, GitHub Actions, Docker, ECR, OpenTelemetry OTLP                                    |
| [k8s-manifests](https://github.com/beginner349/k8s-manifests)     | Kubernetes workload definitions | Kustomize, Helm, External Secrets Operator, Grafana Alloy                                           |

`platform-infra` provisions the cloud substrate (VPC, EKS cluster, ECS, IAM, networking). `k8s-manifests` deploys the application and supporting tooling (ESO, Grafana Alloy) onto the EKS cluster that this repo creates. `beginner349-app` is the workload itself — it ships to ECR via CI/CD and is deployed by `k8s-manifests`.

---

## Project Overview

  ```mermaid
  flowchart TD
    subgraph Repos ["GitHub Repositories"]
      repo_infra["platform-infra\n(Terraform)"]
      repo_app["beginner349-app\n(Spring Boot 4.0)"]
      repo_k8s["k8s-manifests\n(Kustomize + Helm)"]
    end

    subgraph CI_CD_App ["CI/CD: Application"]
      gha_app["GitHub Actions\nmvn build + Docker"]
      ecr[("Amazon ECR")]
    end

    subgraph CI_CD_Infra ["CI/CD: Infrastructure"]
      gha_tf["GitHub Actions\nTerraform Deploy"]
      oidc_tf["OIDC (Passwordless Auth)"]
    end

    subgraph Grafana_Cloud ["Grafana Cloud (SaaS)"]
      grafana["Metrics / Logs / Traces\nDashboards"]
    end

    subgraph AWS_Cloud ["AWS Cloud (ap-southeast-1)"]
      secrets_mgr["AWS Secrets Manager\ndev/grafana-cloud/*\nAurora DB creds"]
      dynamodb[("DynamoDB")]
      s3[("S3 Backend\nTF State + Lock")]
      route53["Route53\nauth.beginner349.com"]
      acm["ACM SSL Cert"]

      subgraph VPC ["Custom VPC (10.0.0.0/16)"]
        subgraph Public ["Public Subnets"]
          alb_kc["ALB: Keycloak\nHTTP → HTTPS redirect\nSSL Termination"]
          alb_app["ALB: Spring Boot App"]
        end

        subgraph Private ["Private Subnets"]
          subgraph EKS ["Amazon EKS (Auto Mode, v1.35)"]
            spring_boot["Spring Boot App\nOTLP → :4318"]
            eso["External Secrets Operator\nIRSA: eso-irsa"]
            alloy["Grafana Alloy\n(metrics / logs / traces collector)"]
          end

          subgraph ECS ["ECS Fargate"]
            keycloak["Keycloak 26.6.1\nRealm: pre-imported"]
          end
        end

        subgraph DB ["Database Subnets"]
          aurora[("Aurora PostgreSQL\nServerless v2\n0.5–1.0 ACUs")]
        end
      end
    end
  
    %% Infra CI/CD
    repo_infra --> gha_tf --> oidc_tf
    oidc_tf -- "Terraform Apply" --> AWS_Cloud
    gha_tf -- "State Lock" --> s3

    %% App CI/CD
    repo_app --> gha_app
    gha_app -- "Push image" --> ecr
    ecr -- "Pull image" --> spring_boot
    ecr -- "Pull image" --> keycloak

    %% K8s deploy
    repo_k8s -- "Helm + Kustomize apply" --> EKS

    %% User traffic
    User((User)) --> route53
    route53 --> alb_kc
    acm -- "SSL Cert" --> alb_kc
    alb_kc -- "Port 8080" --> keycloak
    alb_app --> spring_boot

    %% Data persistence
    keycloak --> aurora
    spring_boot --> dynamodb
    secrets_mgr -- "DB password" --> keycloak

    %% Secrets flow (ESO)
    eso -- "IRSA: AssumeRoleWithWebIdentity" --> secrets_mgr
    secrets_mgr -- "Grafana API Token" --> alloy

    %% Observability pipeline
    spring_boot -- "OTLP HTTP :4318" --> alloy
    alloy -- "Remote Write" --> grafana
  ```

---

## Key Design Decisions

- **EKS Auto Mode** — Node provisioning is fully managed; no EC2 node group configuration needed. Demonstrates cluster-level Kubernetes operations without operational overhead.

- **ECS Fargate for Keycloak** — Keycloak is a stateful, long-lived identity service that doesn't benefit from the Kubernetes workload lifecycle. Running it on Fargate isolates it cleanly while keeping it inside the same VPC and behind the same ALB pattern.

- **IRSA over static IAM keys** — Both the External Secrets Operator service account (`external-secrets-sa`) and the Spring Boot service account (`beginner349-sa`) assume IAM roles via OIDC token exchange. No long-lived credentials anywhere in the system.

- **External Secrets Operator for Grafana credentials** — Rather than storing the Grafana Cloud API token in CI/CD variables or a hardcoded Kubernetes Secret, ESO pulls `dev/grafana-cloud/*` from Secrets Manager at runtime and injects it into the Grafana Alloy pod. This is the GitOps-safe secret pattern.

- **Aurora Serverless v2 (0.5–1.0 ACUs)** — Scales to near-zero during idle periods, keeping demo costs negligible without sacrificing a production-like managed relational database architecture.

- **S3 native state locking (`use_lockfile = true`)** — Uses Terraform 1.14's built-in  S3 locking instead of a DynamoDB lock table, reducing the number of resources to  manage.

- **Keycloak realm pre-imported via one-shot ECS task** — `realm.json` is baked into  the custom Keycloak Docker image and imported via a separate ECS task definition at  startup, making the realm configuration version-controlled and the import idempotent.

---

## Platform Infrastructure

The following AWS resources are provisioned by this repository:

| Layer | Resource | Notes |
|---|---|---|
| Compute | EKS Auto Mode (v1.35) | API auth mode; auto-provisioned nodes in private subnets |
| Compute | ECS Fargate | Keycloak container + one-shot realm-import task |
| Database | Aurora PostgreSQL Serverless v2 | 0.5–1.0 ACUs; password auto-managed by Secrets Manager |
| Storage | DynamoDB | Application data for the Spring Boot service |
| Networking | VPC (10.0.0.0/16) | 3 AZs; public / private / database subnets; single NAT gateway |
| Networking | ALB × 2 | Keycloak (HTTPS + HTTP→HTTPS redirect); Spring Boot app |
| DNS / TLS | Route53 + ACM | `auth.beginner349.com` alias record → Keycloak ALB |
| IAM | IRSA: `eks-service-iam-role` | Spring Boot service account → DynamoDB read-only |
| IAM | IRSA: `eso-irsa` | ESO service account → Secrets Manager `dev/grafana-cloud/*` |
| IAM | GitHub OIDC role | Passwordless GitHub Actions → AWS auth (no access keys) |
| IAM | EKS Access Entry | GitHub OIDC role granted cluster-admin for `k8s-manifests` deploys |
| State | S3 Backend + native lock | Bucket name includes account ID for global uniqueness |

---

## Observability Pipeline

The Spring Boot application (`beginner349-app`) is instrumented with the OpenTelemetry Java agent and exports **metrics, logs, and traces** via OTLP HTTP to Grafana Alloy running in the same EKS cluster.

```
Spring Boot (OpenTelemetry agent)
→ OTLP HTTP :4318
    → Grafana Alloy (EKS pod, Helm-deployed via k8s-manifests)
    → Grafana Cloud (unified remote write endpoint)
```

The Grafana Cloud API token is stored in AWS Secrets Manager at `dev/grafana-cloud/api-token`. The External Secrets Operator (deployed by `k8s-manifests`) uses its IRSA role to retrieve the token every hour and sync it into a Kubernetes Secret. Grafana Alloy mounts this secret as an environment variable at runtime — no static credentials in any manifest or CI/CD pipeline.

---

## CI/CD Workflows

### This Repository (`platform-infra`)

| Workflow | Trigger | Purpose |
|---|---|---|
| `terraform-deploy.yml` | Push to `main` or manual dispatch | Runs `terraform plan` then `terraform apply` (gated by `production` environment approval) |
| `terraform-destroy.yml` | Manual dispatch only | Full `terraform destroy` — manual-only trigger prevents accidental teardown |
| `build-keycloak-image.yml` | Manual dispatch only | Builds custom Keycloak image (base `keycloak:26.6.1` + `realm.json`) and pushes to ECR |

All workflows authenticate to AWS via OIDC — no AWS access keys are stored as secrets.

### Application Repository 
([beginner349-app](https://github.com/beginner349/beginner349-app))

| Workflow | Trigger | Purpose |
|---|---|---|
| `maven.yml` | Push to `main` | `mvn clean package` → Docker build → push to ECR (tagged with commit SHA) |

---

## Terraform Reference

### Requirements

| Tool | Version |
|---|---|
| Terraform | `~> 1.14.7` |
| AWS Provider | `~> 6.28` |
| TLS Provider | `4.2.1` |

### Backend Configuration

State is stored in S3 with native file-based locking (no DynamoDB table required):

- **Bucket:** `terraform-state-bucket-<AWS_ACCOUNT_ID>-ap-southeast-1-an`
- **Key:** `terraform/state/platform-infra.tfstate`
- **Region:** `ap-southeast-1`
- **Locking:** `use_lockfile = true`

### Input Variables

All variables are injected as `TF_VAR_*` environment variables from GitHub Actions 
repository variables:

| Name | Description | GitHub Actions Source |
|---|---|---|
| `domain_name` | Root domain for Keycloak (e.g. `beginner349.com`) | `vars.DOMAIN_NAME` |
| `AWS_ROLE_NAME` | IAM role name for OIDC; also used for EKS access entry | `vars.AWS_ROLE_NAME` |
| `keycloak_image_tag` | ECR image tag for the Keycloak container | `vars.KEYCLOAK_IMAGE_TAG` |
| `AWS_ECR` | ECR registry URL | `vars.AWS_ECR` |
| `region` | AWS region | `vars.AWS_DEFAULT_REGION` |

### Outputs

| Name | Description |
|---|---|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | EKS API server endpoint |
| `cluster_security_group_id` | EKS control plane security group ID |
| `alb_dns` | Keycloak ALB DNS name |
| `aurora_cluster_endpoint` | Aurora writer endpoint |
| `aurora_cluster_port` | Aurora port (default: 5432) |
| `aurora_secret_arn` | Secrets Manager ARN for Aurora credentials |
| `rds_username` | Aurora master username |

---

## Repository Structure

```
platform-infra/
├── .github/
│   └── workflows/
│       ├── terraform-deploy.yml       # IaC deploy pipeline (plan → apply with 
approval gate)
│       ├── terraform-destroy.yml      # Manual teardown only
│       └── build-keycloak-image.yml   # Custom Keycloak image build and ECR push
├── Dockerfile                          # Keycloak image with realm.json baked in
├── keycloak/
│   └── realm.json                      # Pre-configured Keycloak realm, client, and 
user
└── terraform/
    ├── main.tf                         # All AWS resources (VPC, ECS, EKS, ALB, IAM, 
Aurora)
    ├── access_entry.tf                 # EKS access entry for GitHub OIDC role
    ├── backend.tf                      # S3 remote state backend configuration
    ├── terraform.tf                    # Provider version constraints
    ├── variables.tf                    # Input variable declarations
    └── outputs.tf                      # Exported resource values
```

## TODO
- [x] Setting Up OpenID Connect (OIDC) in AWS for GitHub Actions
- [x] Configuring an S3 Remote Backend for Terraform State and Locking
- [x] Creating Infrastructure as Code (IaC) for IAM Roles for Service Accounts (IRSA)
- [x] Create import files for Keycloak realms, users, and clients
- [ ] Enable logging and monitoring in the EKS cluster
- [ ] Implement TLS/SSL for the ingress with a custom domain using ExternalDNS and Route 53
