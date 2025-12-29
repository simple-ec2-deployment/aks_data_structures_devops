# Jenkins on EC2 - Complete Setup Guide

This guide shows you how to set up Jenkins **ON** your EC2 instance and have it deploy everything directly on the same EC2 server.

## Architecture

```
┌─────────────────────────────────────────┐
│          EC2 Instance (4GB, 2 CPU)      │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │        Jenkins (Port 8080)        │  │
│  └──────────────────────────────────┘  │
│              │                          │
│              │ Pipeline Execution       │
│              ▼                          │
│  ┌──────────────────────────────────┐  │
│  │   Kubernetes (k3s)               │  │
│  │   - Frontend Pods                │  │
│  │   - Backend Pods                 │  │
│  │   - Database Pod                 │  │
│  │   - Monitoring Pods              │  │
│  └──────────────────────────────────┘  │
│                                         │
└─────────────────────────────────────────┘
```

## Step 1: Set Up EC2 Instance

### 1.1 Install Prerequisites

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo systemctl start docker
sudo systemctl enable docker

# Install k3s (lightweight Kubernetes)
curl -sfL https://get.k3s.io | sh -
sudo kubectl get nodes

# Install Git
sudo apt install git -y

# Install kubectl (if not included with k3s)
sudo apt install kubectl -y
```

### 1.2 Configure Docker for k3s (if needed)

```bash
# k3s uses containerd by default, but we can use Docker
# Make sure Docker is accessible
sudo usermod -aG docker $USER
newgrp docker
```

## Step 2: Install Jenkins on EC2

```bash
# Install Java
sudo apt install openjdk-11-jdk -y

# Add Jenkins repository
wget -q -O - https://pkg.jenkins.io/debian/jenkins.io.key | sudo apt-key add -
sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'

# Install Jenkins
sudo apt update
sudo apt install jenkins -y

# Start Jenkins
sudo systemctl start jenkins
sudo systemctl enable jenkins

# Add Jenkins user to docker group
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# Get initial password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

### 2.1 Access Jenkins

1. Open browser: `http://<EC2-IP>:8080`
2. Enter initial password from above
3. Install recommended plugins
4. Create admin user
5. Configure Jenkins URL

## Step 3: Configure Jenkins Credentials

Go to: **Jenkins → Manage Jenkins → Credentials → System → Global credentials → Add Credentials**

### Required Credential:

**GitHub PAT Token:**
- **Kind**: Secret text
- **ID**: `github-pat-token`
- **Secret**: Your GitHub Personal Access Token
- **Description**: GitHub PAT Token

**That's it!** No EC2 SSH credentials needed since Jenkins is running on EC2.

## Step 4: Create Pipeline Job

1. **New Item** → **Pipeline**
2. **Name**: `main-pipeline`
3. **Pipeline** → **Definition**: Pipeline script from SCM
4. **SCM**: Git
5. **Repository URL**: `https://github.com/simple-ec2-deployment/aks_data_structures_devops.git`
6. **Credentials**: `github-pat-token`
7. **Branch**: `*/main`
8. **Script Path**: `devops-infra/jenkins/Jenkinsfile`
9. Click **Save**

## Step 5: Configure Jenkins User Permissions

Jenkins needs to run Docker and kubectl commands:

```bash
# Add Jenkins user to docker group (already done above)
sudo usermod -aG docker jenkins

# Give Jenkins access to k3s kubeconfig
sudo mkdir -p /var/lib/jenkins/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube
sudo chmod 600 /var/lib/jenkins/.kube/config

# Update kubeconfig to use localhost instead of 127.0.0.1
sudo sed -i 's/127.0.0.1/localhost/g' /var/lib/jenkins/.kube/config

# Restart Jenkins
sudo systemctl restart jenkins
```

## Step 6: Run the Pipeline

1. Go to Jenkins → `main-pipeline`
2. Click **"Build with Parameters"**
3. Configure:
   - **ENVIRONMENT**: `prod`
   - **BRANCH_NAME**: `main`
   - **DEPLOY_FRONTEND**: ✓
   - **DEPLOY_BACKEND**: ✓
   - **DEPLOY_DATA_STRUCTURES**: ✓
   - **DEPLOY_MONITORING**: ✓ (optional)
4. Click **"Build"**

## What the Pipeline Does

1. ✅ **Checkout DevOps repo** (already on EC2)
2. ✅ **Clone Frontend repo** to EC2
3. ✅ **Clone Backend repo** to EC2
4. ✅ **Build Docker images** on EC2
5. ✅ **Deploy to Kubernetes** on EC2 using deployment script
6. ✅ **Verify deployment** on EC2

Everything happens **on the same EC2 instance**!

## Troubleshooting

### Jenkins Can't Run Docker

```bash
# Add Jenkins to docker group
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# Test
sudo -u jenkins docker ps
```

### Jenkins Can't Access kubectl

```bash
# Copy kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config
sudo chown jenkins:jenkins /var/lib/jenkins/.kube/config
sudo chmod 600 /var/lib/jenkins/.kube/config

# Test
sudo -u jenkins kubectl get nodes
```

### Pipeline Fails to Clone Repos

- Verify GitHub PAT token has `repo` scope
- Check token is correct in Jenkins credentials
- Test manually: `git clone https://<PAT>@github.com/org/repo.git`

### Docker Build Fails

```bash
# Check Docker is running
sudo systemctl status docker

# Check Jenkins can access Docker
sudo -u jenkins docker ps

# Check disk space
df -h
```

### kubectl Apply Fails

```bash
# Check kubeconfig
sudo -u jenkins kubectl config view

# Check cluster access
sudo -u jenkins kubectl get nodes

# Check permissions
sudo -u jenkins kubectl auth can-i create deployments
```

## Security Group Configuration

Ensure EC2 security group allows:
- **Port 22**: SSH (for your access)
- **Port 8080**: Jenkins web UI
- **Port 80**: HTTP (for ingress)
- **Port 443**: HTTPS (for ingress)
- **Port 30000-32767**: NodePort range (for Kubernetes services)

## Accessing the Application

After deployment:

```bash
# Get ingress IP
kubectl get ingress

# Or port-forward
kubectl port-forward svc/frontend-service 8080:80
# Access: http://localhost:8080
```

## Next Steps

1. Set up GitHub webhooks for automatic deployments
2. Configure SSL/TLS with cert-manager
3. Set up monitoring alerts
4. Configure database backups

---

**Everything runs on one EC2 instance - simple and efficient!** 🚀

