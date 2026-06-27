# DevOps Demo — AWS Infrastructure (Terraform)

Production-grade, modular Terraform IaC for a full AWS stack: VPC, EKS, ECR, and RDS.

---

## Architecture

```
                        ┌─────────────────────────────────────────────────────┐
                        │                   AWS us-east-1                      │
                        │                                                       │
                        │  ┌──────────────────────────────────────────────┐   │
                        │  │                    VPC                        │   │
                        │  │  10.x.0.0/16                                  │   │
                        │  │                                               │   │
                        │  │  ┌─────────────┐  ┌─────────────┐  ┌──────┐ │   │
   Internet ────────────┼──┼─►│ Public Subn │  │ Public Subn │  │ Pub  │ │   │
                        │  │  │  us-east-1a │  │  us-east-1b │  │  1c  │ │   │
                        │  │  │  IGW / NAT  │  │  IGW / NAT  │  │ NAT  │ │   │
                        │  │  └──────┬──────┘  └──────┬──────┘  └──┬───┘ │   │
                        │  │         │                 │             │     │   │
                        │  │  ┌──────▼──────┐  ┌──────▼──────┐  ┌──▼───┐ │   │
                        │  │  │Private Subn │  │Private Subn │  │ Priv │ │   │
                        │  │  │  us-east-1a │  │  us-east-1b │  │  1c  │ │   │
                        │  │  │             │  │             │  │      │ │   │
                        │  │  │ ┌─────────┐ │  │ ┌─────────┐ │  │      │ │   │
                        │  │  │ │EKS Nodes│ │  │ │EKS Nodes│ │  │      │ │   │
                        │  │  │ └────┬────┘ │  │ └────┬────┘ │  │      │ │   │
                        │  │  │      │      │  │      │      │  │      │ │   │
                        │  │  │ ┌────▼────┐ │  │ ┌────▼────┐ │  │      │ │   │
                        │  │  │ │   RDS   │ │  │ │  RDS    │ │  │      │ │   │
                        │  │  │ │(standby)│ │  │ │(primary)│ │  │      │ │   │
                        │  │  │ └─────────┘ │  │ └─────────┘ │  │      │ │   │
                        │  │  └─────────────┘  └─────────────┘  └──────┘ │   │
                        │  └──────────────────────────────────────────────┘   │
                        │                                                       │
                        │  ┌────────────┐     ┌───────────────────────────┐   │
                        │  │    ECR     │     │   EKS Control Plane       │   │
                        │  │ Repos:     │     │   (AWS Managed)           │   │
                        │  │  api       │     │   + Pod Identity Agent    │   │
                        │  │  worker    │     └───────────────────────────┘   │
                        │  │  frontend  │                                       │
                        │  └────────────┘                                       │
                        └─────────────────────────────────────────────────────┘
```

---

## Project Structure

```
iac/
├── modules/
│   ├── vpc/          VPC, subnets, IGW, NAT GWs, route tables, security groups
│   ├── eks/          EKS cluster, node groups, addons, Pod Identity
│   ├── ecr/          ECR repositories with lifecycle policies
│   └── rds/          RDS instance, subnet group, parameter group, monitoring
│
├── stacks/
│   ├── dev/          Dev environment stack (wires modules)
│   └── prod/         Prod environment stack
│
├── params/
│   ├── dev.tfvars    Dev input values
│   └── prod.tfvars   Prod input values
│
├── backend/
│   └── backend.tf    S3 state bucket — native locking (bootstrap once)
│
├── scripts/
│   ├── apply.sh      Deploy a stack
│   ├── destroy.sh    Destroy a stack
│   └── kubeconfig.sh Refresh kubeconfig
│
├── examples/
│   └── k8s-pod-identity/  Kubernetes manifests using Pod Identity
│
├── Makefile
└── README.md
```

---

## Naming Convention

```
<project>-<environment>-<resource>

Examples:
  devops-demo-dev-eks
  devops-demo-prod-vpc
  devops-demo-dev-postgres
```

---

## Tagging

All resources carry:

| Tag         | Value                     |
|-------------|---------------------------|
| Project     | devops-demo               |
| Environment | dev / prod                |
| ManagedBy   | terraform                 |
| Owner       | devops-team               |

---

## Prerequisites

| Tool        | Minimum Version |
|-------------|-----------------|
| Terraform   | 1.11.0          |
| AWS provider| ~> 6.0          |
| AWS CLI     | 2.x             |
| kubectl     | 1.31+           |
| make        | GNU Make 4+     |

AWS credentials must be configured (`aws configure` or instance/role).

---

## Quick Start

### 1. Bootstrap backend (run once per AWS account)

```bash
make bootstrap
```

Creates:
- S3 bucket: `devops-demo-tfstate-<account-id>` (versioned, encrypted)

> State locking is handled by S3 natively via `use_lockfile=true` — no DynamoDB table is needed (requires Terraform >= 1.11).

### 2. Set the DB password

```bash
export TF_VAR_rds_db_password="ChangeMeToSomethingSecure!"
```

> In CI/CD use AWS Secrets Manager or Vault to inject this.

### 3. Plan

```bash
make plan ENV=dev
```

### 4. Apply

```bash
make apply ENV=dev
```

The script will:
1. Validate AWS credentials
2. Init Terraform with S3 backend
3. Run `terraform plan`
4. Prompt for confirmation
5. Apply
6. Run `aws eks update-kubeconfig` automatically

### 5. Verify cluster access

```bash
kubectl get nodes
kubectl get pods -A
```

---

## EKS Pod Identity

This project uses **EKS Pod Identity** (not IRSA).

### How it works

```
┌────────────────────────────────────────────────────────┐
│  Pod (Namespace: app, SA: api-service-account)         │
│                                                         │
│  AWS SDK calls → http://169.254.170.23/...             │
│                         │                               │
│                         ▼                               │
│       eks-pod-identity-agent (DaemonSet on Node)        │
│                         │                               │
│                         ▼ sts:AssumeRole                │
│              IAM Role: devops-demo-dev-pod-api-s3       │
│                         │                               │
│                         ▼                               │
│              Temporary STS Credentials                  │
│              returned to the SDK                        │
└────────────────────────────────────────────────────────┘
```

### Trust policy on the IAM role (Terraform-managed)

```json
{
  "Effect": "Allow",
  "Principal": { "Service": "pods.eks.amazonaws.com" },
  "Action": ["sts:AssumeRole", "sts:TagSession"],
  "Condition": {
    "StringEquals": { "aws:SourceAccount": "<account-id>" },
    "ArnLike":      { "aws:SourceArn": "<cluster-arn>" }
  }
}
```

### Terraform wiring

```hcl
eks_pod_identity_associations = {
  api-s3 = {
    namespace           = "app"
    service_account     = "api-service-account"
    managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
  }
}
```

### Kubernetes side — no annotations needed

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-service-account
  namespace: app
# No annotations — Pod Identity is entirely AWS-side
```

### Verify it works

```bash
kubectl apply -f examples/k8s-pod-identity/
kubectl logs -n app job/s3-identity-test
```

---

## Environments

| Parameter               | dev            | prod           |
|-------------------------|----------------|----------------|
| VPC CIDR                | 10.10.0.0/16   | 10.20.0.0/16   |
| NAT Gateways            | 1 (cost saving)| 3 (one per AZ) |
| EKS instance type       | t3.medium      | m6i.xlarge     |
| EKS node min/max        | 1–3            | 2–10           |
| Spot node group         | ✗              | ✓              |
| RDS class               | db.t3.medium   | db.r6g.large   |
| RDS Multi-AZ            | ✗              | ✓              |
| RDS retention           | 3 days         | 30 days        |
| Deletion protection     | ✗              | ✓              |
| ECR tag mutability      | MUTABLE        | IMMUTABLE      |
| EKS public endpoint     | ✓              | ✗ (private)    |

---

## Common Operations

```bash
# Format all .tf files
make fmt

# Validate without connecting to backend
make validate ENV=dev

# Show current outputs
make output ENV=dev

# Refresh kubeconfig only
make kubeconfig ENV=dev

# Destroy dev (with confirmation)
make destroy ENV=dev
```

---

## State Management

- **Backend**: S3 with AES-256 encryption and versioning
- **Locking**: S3 native locking (`use_lockfile=true`) — a lock object in the bucket prevents concurrent applies (requires Terraform >= 1.11)
- **State per env**: `s3://<bucket>/dev/terraform.tfstate`

---

## Security Notes

- RDS password is never stored in tfvars — use `TF_VAR_rds_db_password`
- IAM roles follow least-privilege; no `*:*` policies
- EKS public endpoint disabled in prod
- All subnets, S3 buckets, and RDS storage are encrypted
- ECR images are immutable in prod (prevents tag overwrite)
