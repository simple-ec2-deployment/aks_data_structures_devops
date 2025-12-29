# Jenkins EC2 SSH Configuration - Quick Reference

## Where to Configure EC2 SSH in Jenkins

### Location: Jenkins → Manage Jenkins → Credentials → System → Global credentials

## Required Credentials

Add these **3 credentials** in Jenkins:

### 1. EC2 Host (IP Address)
- **Path**: Jenkins → Manage Jenkins → Credentials → Add Credentials
- **Kind**: Secret text
- **ID**: `ec2-host`
- **Secret**: Your EC2 IP (e.g., `54.123.45.67`)

### 2. EC2 SSH Key
- **Path**: Jenkins → Manage Jenkins → Credentials → Add Credentials
- **Kind**: SSH Username with private key
- **ID**: `ec2-ssh-key`
- **Username**: `ubuntu` (or `ec2-user`)
- **Private Key**: Paste your `.pem` file content

### 3. EC2 User (Optional)
- **Path**: Jenkins → Manage Jenkins → Credentials → Add Credentials
- **Kind**: Secret text
- **ID**: `ec2-user`
- **Secret**: `ubuntu` (or `ec2-user`)

## What Happens When Pipeline Runs

1. **Jenkins clones DevOps repo** locally
2. **Jenkins SSHs into EC2** using `ec2-ssh-key`
3. **On EC2**: Clones all 3 repos (devops, frontend, backend)
4. **On EC2**: Builds Docker images
5. **On EC2**: Deploys to Kubernetes
6. **On EC2**: Verifies deployment

## Files Updated

- ✅ `devops-infra/jenkins/Jenkinsfile` - Added EC2 SSH deployment stage
- ✅ `devops-infra/jenkins/JENKINS_EC2_SETUP.md` - Detailed setup guide
- ✅ `devops-infra/jenkins/JENKINS_CREDENTIALS_SETUP.md` - Step-by-step credential setup

## Quick Test

After adding credentials, run the pipeline:
1. Go to Jenkins → `main-pipeline`
2. Click "Build with Parameters"
3. Select your options
4. Click "Build"

The pipeline will automatically SSH into EC2 and deploy everything!

---

**For detailed instructions, see:**
- `devops-infra/jenkins/JENKINS_CREDENTIALS_SETUP.md` - How to add credentials
- `devops-infra/jenkins/JENKINS_EC2_SETUP.md` - Complete setup guide

