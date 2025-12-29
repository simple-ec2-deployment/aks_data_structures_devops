# Deployment Guide

Complete guide for deploying the AKS Data Structures Platform.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Local Development Setup](#local-development-setup)
3. [AWS Deployment](#aws-deployment)
4. [Jenkins CI/CD Setup](#jenkins-cicd-setup)
5. [Monitoring Setup](#monitoring-setup)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools

- **Docker** >= 20.10
- **kubectl** >= 1.28
- **Terraform** >= 1.0.0
- **Helm** >= 3.0
- **Minikube** (for local) or **AWS CLI** (for cloud)
- **Jenkins** (for CI/CD)

### Required Access

- AWS Account with appropriate IAM permissions
- GitHub repository access
- Container registry access (ECR/Docker Hub)

## Local Development Setup

### 1. Start Minikube

```bash
# Start Minikube
minikube start --memory=4096 --cpus=2

# Configure Docker to use Minikube
eval $(minikube docker-env)

# Verify
kubectl get nodes
```

### 2. Deploy Namespace

```bash
kubectl apply -f kubernetes/namespaces/namespace.yaml
```

### 3. Deploy Database

```bash
# Create secrets (update with your values)
kubectl apply -f kubernetes/database/secret.yaml

# Deploy PostgreSQL
kubectl apply -f kubernetes/database/pvc.yaml
kubectl apply -f kubernetes/database/service.yaml
kubectl apply -f kubernetes/database/statefulset.yaml

# Wait for database to be ready
kubectl wait --for=condition=ready pod -l app=postgres --timeout=300s
```

### 4. Deploy Backend

```bash
# Create secrets and configmaps
kubectl apply -f kubernetes/backend/secret.yaml
kubectl apply -f kubernetes/backend/configmap.yaml

# Deploy backend
kubectl apply -f kubernetes/backend/deployment.yaml
kubectl apply -f kubernetes/backend/service.yaml
kubectl apply -f kubernetes/backend/hpa.yaml

# Verify
kubectl get pods -l app=backend
```

### 5. Deploy Frontend

```bash
# Create configmap
kubectl apply -f kubernetes/frontend/configmap.yaml

# Deploy frontend
kubectl apply -f kubernetes/frontend/deployment.yaml
kubectl apply -f kubernetes/frontend/service.yaml
kubectl apply -f kubernetes/frontend/hpa.yaml

# Verify
kubectl get pods -l app=frontend
```

### 6. Deploy Ingress

```bash
# Deploy NGINX Ingress Controller
kubectl apply -f kubernetes/ingress-controller/nginx-ingress-controller.yaml

# Deploy Ingress rules
kubectl apply -f kubernetes/ingress/ingress.yaml

# Get ingress IP
minikube service ingress-nginx-controller
```

### 7. Deploy Monitoring (Optional)

```bash
# Deploy Prometheus
kubectl apply -f kubernetes/monitoring/prometheus/clusterrole.yaml
kubectl apply -f kubernetes/monitoring/prometheus/configmap.yaml
kubectl apply -f kubernetes/monitoring/prometheus/alerts.yaml
kubectl apply -f kubernetes/monitoring/prometheus/deployment.yaml
kubectl apply -f kubernetes/monitoring/prometheus/service.yaml

# Deploy Grafana
kubectl apply -f kubernetes/monitoring/grafana/configmap.yaml
kubectl apply -f kubernetes/monitoring/grafana/deployment.yaml
kubectl apply -f kubernetes/monitoring/grafana/service.yaml
```

## AWS Deployment

### 1. Configure AWS Credentials

```bash
aws configure
# Enter AWS Access Key ID
# Enter AWS Secret Access Key
# Enter default region (e.g., us-east-1)
```

### 2. Configure Terraform

```bash
cd terraform/environments/dev

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars
vim terraform.tfvars
```

**Example terraform.tfvars:**
```hcl
project_name = "aks-data-structures"
aws_region   = "us-east-1"
environment  = "dev"

# VPC Configuration
vpc_cidr            = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]

# Kubernetes Configuration
namespace           = "default"
frontend_replicas   = 2
backend_replicas    = 2

# Image Configuration
frontend_image = "your-registry/frontend:latest"
backend_image  = "your-registry/backend:latest"
```

### 3. Initialize and Apply Terraform

```bash
# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply
```

### 4. Configure kubectl

```bash
# Get kubeconfig from Terraform output
terraform output kubeconfig > kubeconfig.yaml

# Set KUBECONFIG
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Verify
kubectl get nodes
```

### 5. Deploy Application

Follow steps 3-7 from [Local Development Setup](#local-development-setup).

## Jenkins CI/CD Setup

### 1. Install Jenkins

```bash
# Using Helm
helm repo add jenkins https://charts.jenkins.io
helm install jenkins jenkins/jenkins \
  --set controller.serviceType=NodePort \
  --set controller.serviceNodePort=30080

# Get admin password
kubectl exec --namespace default -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password
```

### 2. Configure Jenkins

1. Access Jenkins UI: `http://<jenkins-ip>:30080`
2. Install recommended plugins
3. Configure credentials:
   - **GitHub PAT**: `github-pat-token`
   - **Docker Registry**: `docker-registry-credentials`
   - **Kubeconfig**: `kubeconfig`

### 3. Create Pipeline Jobs

#### Main Pipeline

1. New Item → Pipeline
2. Name: `main-pipeline`
3. Pipeline Definition: Pipeline script from SCM
4. SCM: Git
5. Repository URL: Your DevOps repo URL
6. Script Path: `devops-infra/jenkins/Jenkinsfile`

#### Frontend Pipeline

1. New Item → Pipeline
2. Name: `frontend-pipeline`
3. Pipeline Definition: Pipeline script from SCM
4. SCM: Git
5. Repository URL: Your DevOps repo URL
6. Script Path: `devops-infra/jenkins/Jenkinsfile.frontend`

#### Backend Pipeline

1. New Item → Pipeline
2. Name: `backend-pipeline`
3. Pipeline Definition: Pipeline script from SCM
4. SCM: Git
5. Repository URL: Your DevOps repo URL
6. Script Path: `devops-infra/jenkins/Jenkinsfile.backend`

### 4. Configure GitHub Webhooks

1. Go to GitHub repository settings
2. Webhooks → Add webhook
3. Payload URL: `http://<jenkins-ip>:30080/github-webhook/`
4. Content type: `application/json`
5. Events: `Just the push event`
6. Active: ✓

### 5. Trigger Pipeline

```bash
# Manual trigger
# Go to Jenkins UI → Select pipeline → Build with Parameters

# Or via webhook (automatic on git push)
git push origin main
```

## Monitoring Setup

### Access Prometheus

```bash
# Port forward
kubectl port-forward svc/prometheus-service 9090:9090

# Access
open http://localhost:9090
```

### Access Grafana

```bash
# Port forward
kubectl port-forward svc/grafana-service 3000:3000

# Access
open http://localhost:3000

# Default credentials
# Username: admin
# Password: admin123 (change on first login)
```

### Import Dashboards

1. Go to Grafana → Dashboards → Import
2. Upload dashboard JSON files:
   - `kubernetes/monitoring/grafana/dashboards/flask-dashboard.json`
   - `kubernetes/monitoring/grafana/dashboards/kubernetes-dashboard.json`

## Troubleshooting

### Common Issues

#### Pods in CrashLoopBackOff

```bash
# Check logs
kubectl logs <pod-name>

# Check events
kubectl describe pod <pod-name>

# Common causes:
# - Missing secrets/configmaps
# - Wrong image tag
# - Resource limits too low
```

#### Database Connection Failed

```bash
# Check database pod
kubectl get pods -l app=postgres

# Check database logs
kubectl logs <postgres-pod>

# Verify secrets
kubectl get secret postgres-secrets -o yaml

# Test connection
kubectl exec -it <postgres-pod> -- psql -U appuser -d appdb
```

#### Jenkins Pipeline Fails

```bash
# Check Jenkins logs
kubectl logs <jenkins-pod>

# Verify credentials in Jenkins UI
# Jenkins → Manage Jenkins → Credentials

# Check pipeline console output
# Jenkins → Pipeline → Console Output
```

#### Images Not Found

```bash
# For Minikube, ensure Docker is pointing to Minikube
eval $(minikube docker-env)

# Build images locally
docker build -t backend-service:latest <path-to-backend>
docker build -t ui-service:latest <path-to-frontend>

# For AWS, ensure images are pushed to registry
docker push <registry>/backend-service:latest
docker push <registry>/ui-service:latest
```

### Health Check Endpoints

```bash
# Backend health
curl http://<backend-service-ip>:5000/health
curl http://<backend-service-ip>:5000/health/ready
curl http://<backend-service-ip>:5000/health/live
curl http://<backend-service-ip>:5000/metrics

# Frontend health
curl http://<frontend-service-ip>:80/health
```

### Useful Commands

```bash
# Get all resources
kubectl get all

# Get pods with details
kubectl get pods -o wide

# Get services
kubectl get svc

# Get ingress
kubectl get ingress

# Describe resource
kubectl describe <resource-type> <resource-name>

# Logs
kubectl logs <pod-name> -f

# Exec into pod
kubectl exec -it <pod-name> -- /bin/sh

# Port forward
kubectl port-forward svc/<service-name> <local-port>:<remote-port>
```

## Next Steps

1. Set up production environment
2. Configure SSL/TLS with cert-manager
3. Set up log aggregation (EFK/Loki)
4. Configure backup strategy for database
5. Set up distributed tracing (Jaeger)
6. Implement service mesh (Istio/Linkerd)

---

For more information, see the main [README.md](../README.md).

