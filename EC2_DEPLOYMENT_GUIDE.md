# EC2 Deployment Guide - One-Click Deployment

Complete guide for deploying the AKS Data Structures Platform on a single EC2 instance (4GB RAM, 2 CPU).

## Prerequisites

### EC2 Instance Requirements

- **Instance Type**: t3.medium or similar (4GB RAM, 2 vCPU minimum)
- **OS**: Ubuntu 20.04 LTS or later / Amazon Linux 2
- **Storage**: 20GB minimum free space
- **Network**: Security group allowing:
  - Port 22 (SSH)
  - Port 80 (HTTP)
  - Port 443 (HTTPS)
  - Port 30000-32767 (NodePort range for Kubernetes)

### Required Tools

- Docker
- Kubernetes (k3s, k0s, or minikube)
- kubectl
- Git
- Jenkins (for CI/CD)

## Quick Start - One-Click Deployment

### Option 1: Using Jenkins Pipeline (Recommended)

1. **Set up Jenkins on EC2**
   ```bash
   # Install Jenkins
   sudo apt update
   sudo apt install openjdk-11-jdk -y
   wget -q -O - https://pkg.jenkins.io/debian/jenkins.io.key | sudo apt-key add -
   sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
   sudo apt update
   sudo apt install jenkins -y
   sudo systemctl start jenkins
   sudo systemctl enable jenkins
   ```

2. **Install Kubernetes (k3s - lightweight)**
   ```bash
   curl -sfL https://get.k3s.io | sh -
   sudo kubectl get nodes
   ```

3. **Configure Jenkins**
   - Access Jenkins: `http://<EC2-IP>:8080`
   - Get initial password: `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`
   - Install recommended plugins
   - Create credentials:
     - **GitHub PAT Token**: `github-pat-token` (Secret text)
     - **Docker Registry** (if using): `docker-registry-credentials`
     - **Kubeconfig**: `kubeconfig` (Secret file - copy from `/etc/rancher/k3s/k3s.yaml`)

4. **Create Pipeline Jobs**

   **Main Pipeline:**
   - New Item → Pipeline
   - Name: `main-pipeline`
   - Pipeline Definition: Pipeline script from SCM
   - SCM: Git
   - Repository URL: Your DevOps repo URL
   - Credentials: `github-pat-token`
   - Script Path: `devops-infra/jenkins/Jenkinsfile`

   **Frontend Pipeline:**
   - New Item → Pipeline
   - Name: `frontend-pipeline`
   - Pipeline Definition: Pipeline script from SCM
   - SCM: Git
   - Repository URL: Your DevOps repo URL
   - Credentials: `github-pat-token`
   - Script Path: `devops-infra/jenkins/Jenkinsfile.frontend`

   **Backend Pipeline:**
   - New Item → Pipeline
   - Name: `backend-pipeline`
   - Pipeline Definition: Pipeline script from SCM
   - SCM: Git
   - Repository URL: Your DevOps repo URL
   - Credentials: `github-pat-token`
   - Script Path: `devops-infra/jenkins/Jenkinsfile.backend`

   **Data Structures Pipeline:**
   - New Item → Pipeline
   - Name: `data-structures-pipeline`
   - Pipeline Definition: Pipeline script from SCM
   - SCM: Git
   - Repository URL: Your DevOps repo URL
   - Credentials: `github-pat-token`
   - Script Path: `devops-infra/jenkins/Jenkinsfile.data-structures`

5. **Run Main Pipeline**
   - Go to Jenkins → `main-pipeline`
   - Click "Build with Parameters"
   - Select:
     - ENVIRONMENT: `prod`
     - BRANCH_NAME: `main`
     - DEPLOY_FRONTEND: ✓
     - DEPLOY_BACKEND: ✓
     - DEPLOY_DATA_STRUCTURES: ✓
     - DEPLOY_MONITORING: ✓ (optional)
   - Click "Build"

### Option 2: Manual Deployment Script

1. **Clone the DevOps repository**
   ```bash
   git clone https://github.com/<your-org>/aks_data_structures_devops.git
   cd aks_data_structures_devops
   ```

2. **Make deployment script executable**
   ```bash
   chmod +x devops-infra/scripts/deploy-ec2.sh
   ```

3. **Run deployment**
   ```bash
   # Deploy with monitoring
   ./devops-infra/scripts/deploy-ec2.sh prod true
   
   # Deploy without monitoring
   ./devops-infra/scripts/deploy-ec2.sh prod false
   ```

## Resource Allocation (Optimized for 4GB RAM, 2 CPU)

The deployment is optimized for small EC2 instances:

| Service | Replicas | CPU Request | CPU Limit | Memory Request | Memory Limit |
|---------|----------|-------------|-----------|----------------|--------------|
| Frontend | 1 | 50m | 100m | 64Mi | 128Mi |
| Backend | 1 | 100m | 300m | 128Mi | 256Mi |
| Database | 1 | 200m | 500m | 256Mi | 512Mi |
| Prometheus | 1 | 100m | 200m | 128Mi | 256Mi |
| Grafana | 1 | 50m | 100m | 64Mi | 128Mi |
| Ingress | 1 | 50m | 100m | 64Mi | 128Mi |
| **Total** | **6** | **~550m** | **~1300m** | **~896Mi** | **~1472Mi** |

This leaves ~2.5GB RAM and ~700m CPU for Kubernetes system components.

## Jenkins Pipeline Configuration

### GitHub PAT Token Setup

1. Create a GitHub Personal Access Token:
   - Go to GitHub → Settings → Developer settings → Personal access tokens
   - Generate new token with `repo` scope
   - Copy the token

2. Add to Jenkins:
   - Jenkins → Manage Jenkins → Credentials
   - Add Credentials:
     - Kind: Secret text
     - Secret: `<your-github-pat-token>`
     - ID: `github-pat-token`
     - Description: GitHub PAT Token

### Repository URLs

The Jenkins pipelines automatically detect repository URLs based on the DevOps repo URL:

- **DevOps Repo**: Cloned automatically
- **Frontend Repo**: `https://github.com/<org>/aks_data_structures_frontend.git`
- **Backend Repo**: `https://github.com/<org>/aks_data_structures_backend.git`

Make sure all three repositories are accessible with the PAT token.

## Building Docker Images

The Jenkins pipelines will:

1. **Clone all repositories** using PAT token
2. **Build Docker images** locally (using k3s Docker daemon)
3. **Tag images** with build number and git SHA
4. **Deploy to Kubernetes** using manifests or Helm

### For k3s, configure Docker:

```bash
# k3s uses containerd, but we can use Docker
sudo systemctl start docker
sudo systemctl enable docker

# Or use k3s's containerd
# Images built with Docker will be available to k3s
```

## Accessing the Application

After deployment:

1. **Get Ingress IP/Hostname:**
   ```bash
   kubectl get ingress
   ```

2. **Access Services:**
   - Frontend: `http://<ingress-ip>/`
   - Backend API: `http://<ingress-ip>/api/`
   - Prometheus: `http://<ingress-ip>/prometheus/`
   - Grafana: `http://<ingress-ip>/grafana/` (admin/admin123)

3. **Port Forward (Alternative):**
   ```bash
   # Frontend
   kubectl port-forward svc/frontend-service 8080:80
   
   # Backend
   kubectl port-forward svc/backend-service 5000:5000
   
   # Prometheus
   kubectl port-forward svc/prometheus-service 9090:9090
   
   # Grafana
   kubectl port-forward svc/grafana-service 3000:3000
   ```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods

# Check pod logs
kubectl logs <pod-name>

# Describe pod for events
kubectl describe pod <pod-name>

# Check resource usage
kubectl top pods
```

### Out of Memory

If pods are being killed due to OOM:

```bash
# Check node resources
kubectl describe node

# Reduce resource limits in deployment files
# Edit: devops-infra/kubernetes/*/deployment.yaml
```

### Jenkins Pipeline Fails

```bash
# Check Jenkins logs
sudo journalctl -u jenkins -f

# Check pipeline console output in Jenkins UI
# Verify credentials are correct
# Ensure PAT token has repo access
```

### Database Connection Issues

```bash
# Check database pod
kubectl get pods -l app=postgres

# Check database logs
kubectl logs <postgres-pod>

# Test connection
kubectl exec -it <postgres-pod> -- psql -U appuser -d appdb
```

### Images Not Found

```bash
# For k3s, ensure images are built locally
docker images

# If using Docker, import to k3s
sudo k3s ctr images import <image-tar>

# Or build directly in k3s namespace
sudo k3s ctr images pull <image-name>
```

## Monitoring Resource Usage

```bash
# Install metrics server (if not installed)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Check resource usage
kubectl top nodes
kubectl top pods

# Check resource requests/limits
kubectl describe node
```

## Scaling Considerations

With 4GB RAM and 2 CPU:

- **Current setup**: 1 replica per service (fits comfortably)
- **HPA configured**: Min 1, Max 2 replicas
- **Can scale to 2 replicas** if needed (will use ~1.8GB RAM, ~1.1 CPU)

To scale manually:
```bash
kubectl scale deployment frontend-deployment --replicas=2
kubectl scale deployment backend-deployment --replicas=2
```

## Production Checklist

- [ ] All secrets updated with production values
- [ ] Database backups configured
- [ ] Monitoring and alerting set up
- [ ] SSL/TLS certificates configured (optional)
- [ ] Log aggregation configured (optional)
- [ ] Backup strategy implemented
- [ ] Disaster recovery plan documented
- [ ] Security groups properly configured
- [ ] Regular updates scheduled

## Next Steps

1. **Set up SSL/TLS** with cert-manager
2. **Configure backups** for database
3. **Set up log aggregation** (EFK/Loki)
4. **Configure alerts** in Prometheus/Grafana
5. **Set up CI/CD webhooks** for automatic deployments

## Support

For issues or questions:
- Check logs: `kubectl logs <pod-name>`
- Check events: `kubectl get events`
- Review Jenkins pipeline console output
- Check resource usage: `kubectl top pods`

---

**Note**: This deployment is optimized for a single EC2 instance. For production environments with higher traffic, consider:
- Larger instance types
- Multiple nodes
- Managed Kubernetes (EKS)
- Load balancers
- Auto-scaling groups

