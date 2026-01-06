# AKS Data Structures Platform - One-Click Deployment

This guide provides comprehensive one-click deployment scripts for the AKS Data Structures Platform.

## Quick Start

### Prerequisites

- **AWS Infrastructure**: Must be deployed first using `aws-infrastrucutre-terraform/setup.sh`
- **EC2 Instance**: The scripts are designed to run on the EC2 instance created by Terraform
- **SSH Access**: SSH key access to the EC2 instance

### One-Click Commands

#### 1. Deploy Everything
```bash
# SSH into your EC2 instance first
ssh -i aws-infrastrucutre-terraform/modules/ec2/keys/stack_key.pem ubuntu@<EC2_PUBLIC_IP>

# Run the complete setup
cd /home/ubuntu/aks_data_structures_devops/devops-infra
./setup.sh
```

#### 2. Clean Everything
```bash
# Remove all deployed resources
./destroy.sh

# For complete cleanup (including Docker images and Minikube)
./destroy.sh dev true true
```

## Script Details

### setup.sh

The main deployment script that handles:

1. **Prerequisites Check**
   - Docker, kubectl, Minikube, Terraform, Helm, Git, AWS CLI
   - Docker permissions setup
   - Kubernetes connectivity verification

2. **Environment Setup**
   - Minikube configuration (on EC2)
   - kubectl context setup
   - Repository verification

3. **Docker Image Building**
   - Backend service (`backend-service:latest`)
   - Frontend service (`ui-service:latest`)
   - Data structure services (`stack-service`, `linkedlist-service`, `graph-service`)

4. **Kubernetes Deployment**
   - Namespaces creation
   - Frontend, backend, and data structure services
   - Ingress controller and routing
   - Monitoring stack (Prometheus, Grafana)

5. **External Access Setup**
   - Port-forward service on port 80 (EC2)
   - Local port-forward on port 32080 (development)

#### Usage Options

```bash
# Basic usage (default settings)
./setup.sh

# With custom options
./setup.sh <environment> <deploy_monitoring> <use_helm> <skip_build>

# Examples
./setup.sh dev true false false    # Dev environment, with monitoring, kubectl only, build images
./setup.sh prod false true true    # Prod environment, no monitoring, use Helm, skip build
```

#### Parameters

- `environment`: Target environment (default: `dev`)
- `deploy_monitoring`: Deploy Prometheus/Grafana (default: `true`)
- `use_helm`: Use Helm instead of kubectl (default: `false`)
- `skip_build`: Skip Docker image building (default: `false`)

### destroy.sh

The cleanup script that removes:

1. **Port-Forward Services**
   - Systemd service stop/disable (EC2)
   - Background process termination (local)

2. **Kubernetes Resources**
   - All deployments, services, ingress
   - ConfigMaps and Secrets
   - Monitoring namespace and resources
   - Ingress controller

3. **Docker Cleanup**
   - Application image removal
   - Container and image pruning (optional)

4. **Deep Cleanup** (optional)
   - Minikube cluster deletion
   - Generated files removal
   - Repository directory cleanup

#### Usage Options

```bash
# Basic cleanup
./destroy.sh

# Complete cleanup
./destroy.sh dev true true

# Parameters
<environment> <remove_images> <clean_all>
```

#### Parameters

- `environment`: Target environment (default: `dev`)
- `remove_images`: Remove Docker images (default: `true`)
- `clean_all`: Complete cleanup including Minikube (default: `false`)

## Deployment Flow

### 1. AWS Infrastructure (First Time Only)

```bash
cd aws-infrastrucutre-terraform
./setup.sh
```

This creates:
- VPC, subnets, security groups
- EC2 instance with all tools pre-installed
- SSH keys and network configuration

### 2. Application Deployment

```bash
# SSH to EC2
ssh -i aws-infrastrucutre-terraform/modules/ec2/keys/stack_key.pem ubuntu@<EC2_PUBLIC_IP>

# Deploy application
cd /home/ubuntu/aks_data_structures_devops/devops-infra
./setup.sh
```

This deploys:
- All microservices
- Ingress and routing
- External access on port 80
- Monitoring stack

### 3. Access the Application

After successful deployment:

```text
Application is accessible at:
  - Frontend: http://<EC2_PUBLIC_IP>/
  - API:      http://<EC2_PUBLIC_IP>/api/

Monitoring (port-forward required):
  - Prometheus: kubectl port-forward svc/prometheus-service 9090:9090
  - Grafana:    kubectl port-forward svc/grafana-service 3000:3000
```

## Troubleshooting

### Common Issues

#### 1. Port 80 Not Accessible
```bash
# Check if port-forward service is running
sudo systemctl status k8s-port-forward

# Restart if needed
sudo systemctl restart k8s-port-forward

# Check AWS Security Group allows port 80
```

#### 2. Pods Not Starting
```bash
# Check pod status
kubectl get pods -o wide

# View pod logs
kubectl logs -f <pod-name>

# Describe pod for errors
kubectl describe pod <pod-name>
```

#### 3. Docker Build Failures
```bash
# Check Docker permissions
sudo usermod -aG docker ubuntu
# Logout and login again

# Verify Docker daemon
sudo systemctl status docker
```

#### 4. Minikube Issues
```bash
# Check Minikube status
minikube status

# Restart Minikube
minikube stop
minikube start --driver=docker --memory=2500mb --cpus=2
```

### Manual Commands

#### Check Deployment Status
```bash
kubectl get pods -o wide
kubectl get services
kubectl get ingress
kubectl get nodes
```

#### Debug Issues
```bash
# View all resources
kubectl get all --all-namespaces

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp

# Port-forward for debugging
kubectl port-forward svc/frontend-service 8080:80
```

#### Clean Manual Resources
```bash
# Force delete stuck pods
kubectl delete pod <pod-name> --force --grace-period=0

# Clean up specific namespace
kubectl delete namespace <namespace-name> --force --grace-period=0
```

## Advanced Usage

### Custom Configuration

The scripts support customization through environment variables:

```bash
# Set custom environment
export ENVIRONMENT=staging
export DEPLOY_MONITORING=false
export USE_HELM=true

# Run with custom settings
./setup.sh $ENVIRONMENT $DEPLOY_MONITORING $USE_HELM
```

### Development Mode

For local development:

```bash
# Use local Minikube
./setup.sh dev true false false

# Access on localhost:32080
curl http://localhost:32080/
```

### Production Mode

For production deployment:

```bash
# Production settings
./setup.sh prod true false false

# Or with Helm
./setup.sh prod true true false
```

## File Structure

```
devops-infra/
├── setup.sh              # Main deployment script
├── destroy.sh             # Cleanup script
├── README-DEPLOYMENT.md   # This guide
├── jenkins/              # Jenkins pipeline configurations
├── kubernetes/           # Kubernetes manifests
├── helm/                 # Helm charts
├── terraform/            # Terraform configurations
└── scripts/              # Utility scripts
```

## Security Considerations

- **Port 80**: Ensure AWS Security Group allows HTTP traffic
- **SSH Keys**: Protect the private key file (`stack_key.pem`)
- **Docker**: Images are built locally, not pushed to registry
- **Kubernetes**: All resources run in default namespace (simplify for demo)

## Support

For issues:

1. Check the troubleshooting section above
2. Review script logs for error messages
3. Verify AWS infrastructure is deployed correctly
4. Ensure all prerequisites are installed

## Next Steps

After successful deployment:

1. **Monitor**: Set up Grafana dashboards
2. **Scale**: Adjust replica counts in deployment manifests
3. **Backup**: Configure database backups
4. **CI/CD**: Use Jenkins pipelines for automated deployments
