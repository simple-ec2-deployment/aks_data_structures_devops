# Quick Start Guide - EC2 One-Click Deployment

## 🚀 Deploy Everything in 5 Minutes

### Step 1: Set Up EC2 Instance

1. Launch EC2 instance (t3.medium or similar - 4GB RAM, 2 CPU)
2. SSH into the instance
3. Install prerequisites:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install k3s (lightweight Kubernetes)
curl -sfL https://get.k3s.io | sh -
sudo kubectl get nodes

# Install Jenkins
sudo apt install openjdk-11-jdk -y
wget -q -O - https://pkg.jenkins.io/debian/jenkins.io.key | sudo apt-key add -
sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
sudo apt update
sudo apt install jenkins -y
sudo systemctl start jenkins
sudo systemctl enable jenkins

# Add Jenkins to docker group
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### Step 2: Configure Jenkins

1. **Access Jenkins:**
   ```bash
   # Get initial password
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
   Open: `http://<EC2-IP>:8080`

2. **Install Plugins:**
   - Install recommended plugins
   - Install: Git, Docker Pipeline, Kubernetes CLI

3. **Create Credentials:**
   - Go to: Manage Jenkins → Credentials → System → Global credentials
   - Add:
     - **ID**: `github-pat-token`
     - **Type**: Secret text
     - **Secret**: Your GitHub PAT token
     - **Description**: GitHub PAT Token

4. **Configure Kubeconfig:**
   - Copy k3s config:
     ```bash
     sudo cat /etc/rancher/k3s/k3s.yaml
     ```
   - In Jenkins: Add credential
     - **ID**: `kubeconfig`
     - **Type**: Secret file
     - **File**: Paste k3s.yaml content
     - **Description**: K3s Kubeconfig

### Step 3: Create Pipeline Jobs

**Main Pipeline:**
1. New Item → Pipeline → Name: `main-pipeline`
2. Pipeline → Definition: Pipeline script from SCM
3. SCM: Git
4. Repository URL: `https://github.com/<your-org>/aks_data_structures_devops.git`
5. Credentials: `github-pat-token`
6. Branch: `*/main`
7. Script Path: `devops-infra/jenkins/Jenkinsfile`

**Frontend Pipeline:**
- Same as above, but Script Path: `devops-infra/jenkins/Jenkinsfile.frontend`
- Name: `frontend-pipeline`

**Backend Pipeline:**
- Same as above, but Script Path: `devops-infra/jenkins/Jenkinsfile.backend`
- Name: `backend-pipeline`

**Data Structures Pipeline:**
- Same as above, but Script Path: `devops-infra/jenkins/Jenkinsfile.data-structures`
- Name: `data-structures-pipeline`

### Step 4: Run Deployment

1. Go to Jenkins → `main-pipeline`
2. Click **"Build with Parameters"**
3. Select:
   - ENVIRONMENT: `prod`
   - BRANCH_NAME: `main`
   - DEPLOY_FRONTEND: ✓
   - DEPLOY_BACKEND: ✓
   - DEPLOY_DATA_STRUCTURES: ✓
   - DEPLOY_MONITORING: ✓ (optional)
4. Click **"Build"**

### Step 5: Access Your Application

After pipeline completes (5-10 minutes):

```bash
# Get ingress IP
kubectl get ingress

# Or port-forward
kubectl port-forward svc/frontend-service 8080:80
# Access: http://localhost:8080
```

## 📊 Resource Usage

Optimized for **4GB RAM, 2 CPU**:

- **Total Pods**: 6-7 (depending on monitoring)
- **Total CPU Request**: ~550m
- **Total CPU Limit**: ~1300m
- **Total Memory Request**: ~896Mi
- **Total Memory Limit**: ~1472Mi

**Leaves ~2.5GB RAM and ~700m CPU for system components.**

## ✅ Verification

```bash
# Check all pods are running
kubectl get pods

# Check services
kubectl get services

# Check ingress
kubectl get ingress

# View logs
kubectl logs <pod-name>
```

## 🔧 Troubleshooting

**Pods not starting?**
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

**Out of memory?**
- Check: `kubectl top pods`
- Reduce replicas or resource limits

**Jenkins pipeline fails?**
- Check Jenkins console output
- Verify credentials are correct
- Ensure PAT token has repo access

## 📝 What Gets Deployed

1. ✅ **Database** (PostgreSQL) - 1 replica
2. ✅ **Backend** (Flask API) - 1 replica
3. ✅ **Frontend** (React/Vue) - 1 replica
4. ✅ **Data Structures** (Stack, LinkedList, Graph) - 1 replica each
5. ✅ **Ingress Controller** (NGINX)
6. ✅ **Monitoring** (Prometheus + Grafana) - Optional

## 🎯 Next Steps

- Set up GitHub webhooks for automatic deployments
- Configure SSL/TLS certificates
- Set up database backups
- Configure monitoring alerts

---

**For detailed instructions, see [EC2_DEPLOYMENT_GUIDE.md](EC2_DEPLOYMENT_GUIDE.md)**

