# Jenkins EC2 SSH Configuration Guide

This guide explains how to configure Jenkins to SSH into EC2 and deploy the complete application.

## Prerequisites

1. **EC2 Instance Running**
   - EC2 instance with Kubernetes (k3s) installed
   - Jenkins installed on EC2 or on a separate machine
   - SSH access to EC2 instance

2. **SSH Key Pair**
   - EC2 key pair (.pem file) for SSH access
   - Or username/password authentication

## Step 1: Configure Jenkins Credentials

Go to **Jenkins → Manage Jenkins → Credentials → System → Global credentials → Add Credentials**

### 1. EC2 Host (IP or Hostname)

- **Kind**: Secret text
- **ID**: `ec2-host`
- **Secret**: Your EC2 instance IP or hostname (e.g., `54.123.45.67` or `ec2-54-123-45-67.compute-1.amazonaws.com`)
- **Description**: EC2 Instance Host

### 2. EC2 SSH Key

- **Kind**: SSH Username with private key
- **ID**: `ec2-ssh-key`
- **Username**: `ubuntu` (or `ec2-user` for Amazon Linux)
- **Private Key**: Enter directly (paste your .pem file content) OR From a file on Jenkins master
- **Description**: EC2 SSH Private Key

**OR** if using password authentication:

- **Kind**: Username with password
- **ID**: `ec2-ssh-key`
- **Username**: `ubuntu` (or `ec2-user`)
- **Password**: Your EC2 user password
- **Description**: EC2 SSH Credentials

### 3. EC2 User

- **Kind**: Secret text
- **ID**: `ec2-user`
- **Secret**: `ubuntu` (or `ec2-user` for Amazon Linux)
- **Description**: EC2 SSH User

### 4. GitHub PAT Token (Already configured)

- **Kind**: Secret text
- **ID**: `github-pat-token`
- **Secret**: Your GitHub Personal Access Token
- **Description**: GitHub PAT Token

### 5. Kubeconfig (Optional - if Jenkins needs direct kubectl access)

- **Kind**: Secret file
- **ID**: `kubeconfig`
- **File**: Upload your kubeconfig file (from `/etc/rancher/k3s/k3s.yaml` on EC2)
- **Description**: Kubernetes Config

## Step 2: Update Jenkinsfile

The Jenkinsfile has been updated to include EC2 SSH deployment. It will:

1. **Clone DevOps repo** on Jenkins machine
2. **SSH into EC2** using configured credentials
3. **Clone/update repos** on EC2
4. **Run deployment script** on EC2
5. **Verify deployment** on EC2

## Step 3: Alternative - Direct SSH Deployment

If you prefer to deploy directly via SSH without using the deployment script, you can modify the `Deploy to EC2` stage:

```groovy
stage('Deploy to EC2') {
    steps {
        script {
            sh '''
                ssh -i ~/.ssh/ec2_key.pem -o StrictHostKeyChecking=no ${EC2_USER}@${EC2_HOST} << 'ENDSSH'
                    # Clone all three repos
                    if [ -d "aks_data_structures_devops" ]; then
                        cd aks_data_structures_devops && git pull
                    else
                        git clone https://${GITHUB_PAT}@github.com/simple-ec2-deployment/aks_data_structures_devops.git
                        cd aks_data_structures_devops
                    fi
                    
                    if [ -d "../aks_data_structures_frontend" ]; then
                        cd ../aks_data_structures_frontend && git pull
                    else
                        cd .. && git clone https://${GITHUB_PAT}@github.com/simple-ec2-deployment/aks_data_structures_frontend.git
                    fi
                    
                    if [ -d "aks_data_structures_backend" ]; then
                        cd aks_data_structures_backend && git pull
                    else
                        git clone https://${GITHUB_PAT}@github.com/simple-ec2-deployment/aks_data_structures_backend.git
                    fi
                    
                    # Build Docker images
                    cd aks_data_structures_frontend
                    docker build -t ui-service:latest .
                    
                    cd ../aks_data_structures_backend
                    docker build -t backend-service:latest .
                    
                    # Deploy using kubectl
                    cd ../aks_data_structures_devops
                    kubectl apply -f devops-infra/kubernetes/namespaces/
                    kubectl apply -f devops-infra/kubernetes/database/
                    kubectl apply -f devops-infra/kubernetes/backend/
                    kubectl apply -f devops-infra/kubernetes/frontend/
                    kubectl apply -f devops-infra/kubernetes/data-structures/
                    kubectl apply -f devops-infra/kubernetes/ingress/
                    
                    if [ "${DEPLOY_MONITORING}" = "true" ]; then
                        kubectl apply -f devops-infra/kubernetes/monitoring/
                    fi
                ENDSSH
            '''
        }
    }
}
```

## Step 4: Run the Pipeline

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

## How It Works

1. **Jenkins clones DevOps repo** locally
2. **Jenkins SSHs into EC2** using configured credentials
3. **On EC2**: Clones/updates all three repos (devops, frontend, backend)
4. **On EC2**: Builds Docker images
5. **On EC2**: Deploys to Kubernetes using kubectl
6. **On EC2**: Verifies deployment

## Troubleshooting

### SSH Connection Failed

```bash
# Test SSH connection manually
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2-IP>

# Check security group allows port 22
# Verify key permissions: chmod 600 ~/.ssh/your-key.pem
```

### Permission Denied

- Ensure SSH key has correct permissions: `chmod 600`
- Verify username is correct (ubuntu vs ec2-user)
- Check EC2 security group allows SSH from Jenkins IP

### Git Clone Failed on EC2

- Verify GitHub PAT token has repo access
- Check network connectivity from EC2
- Ensure git is installed on EC2: `sudo apt install git -y`

### Docker Build Failed

- Ensure Docker is installed on EC2
- Check Docker daemon is running: `sudo systemctl status docker`
- Verify user has Docker permissions: `sudo usermod -aG docker $USER`

### kubectl Not Found

- Install kubectl on EC2: `sudo apt install kubectl -y`
- Or use k3s kubectl: `sudo k3s kubectl`
- Configure kubeconfig: `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml`

## Security Best Practices

1. **Use SSH keys** instead of passwords
2. **Restrict SSH access** to Jenkins IP in security group
3. **Rotate SSH keys** regularly
4. **Use IAM roles** for EC2 instead of access keys
5. **Store credentials** in Jenkins credential store (not in code)

## Alternative: Jenkins on EC2

If Jenkins is running **on the same EC2 instance** as Kubernetes:

1. You don't need SSH credentials
2. Remove the `Deploy to EC2` stage
3. The pipeline will run directly on EC2
4. Just ensure `kubectl` and `docker` are accessible

---

For more information, see [EC2_DEPLOYMENT_GUIDE.md](../../EC2_DEPLOYMENT_GUIDE.md)

