#!/bin/bash

# Fix Jenkins Configuration Script
# This script will SSH into the EC2 instance and configure Jenkins properly

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() { printf "${GREEN}[JENKINS-FIX]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

# Get EC2 public IP from Terraform output
EC2_IP=$(cd aws-infrastrucutre-terraform/environments/dev && terraform output -raw ec2_public_ip)
SSH_KEY="aws-infrastrucutre-terraform/modules/ec2/keys/stack_key.pem"
chmod 600 aws-infrastrucutre-terraform/modules/ec2/keys/stack_key.pem
if [ -z "$EC2_IP" ]; then
    err "Could not get EC2 public IP"
    exit 1
fi

log "Connecting to EC2 instance at $EC2_IP"

# Create the Jenkins configuration script to run on remote server
cat > /tmp/jenkins_setup.sh << 'EOF'
#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { printf "${GREEN}[REMOTE]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

log "Starting Jenkins configuration fix..."

# Stop Jenkins
log "Stopping Jenkins..."
sudo systemctl stop jenkins

# Create required directories
log "Creating Jenkins directories..."
sudo mkdir -p /var/lib/jenkins/init.groovy.d
sudo mkdir -p /var/lib/jenkins/casc_configs

# Copy configuration files if they exist in the repo
REPO_DIR="/home/ubuntu/aks_data_structures_devops"
if [ -d "$REPO_DIR/devops-infra/jenkins/jenkins-config" ]; then
    log "Copying Jenkins configuration files..."
    
    # Copy JCasC configuration
    sudo cp "$REPO_DIR/devops-infra/jenkins/jenkins-config/jenkins.yaml" /var/lib/jenkins/casc_configs/ 2>/dev/null || warn "Failed to copy jenkins.yaml"
    
    # Copy init groovy scripts
    sudo cp "$REPO_DIR/devops-infra/jenkins/jenkins-config/init.groovy.d/"*.groovy /var/lib/jenkins/init.groovy.d/ 2>/dev/null || warn "Failed to copy groovy scripts"
    
    # Copy plugins.txt
    sudo cp "$REPO_DIR/devops-infra/jenkins/jenkins-config/plugins.txt" /var/lib/jenkins/ 2>/dev/null || warn "Failed to copy plugins.txt"
    
    log "Configuration files copied"
else
    err "Jenkins configuration directory not found at $REPO_DIR"
fi

# Set proper ownership
log "Setting file ownership..."
sudo chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d
sudo chown -R jenkins:jenkins /var/lib/jenkins/casc_configs
sudo chown jenkins:jenkins /var/lib/jenkins/plugins.txt 2>/dev/null || true

# Remove the initial setup lock to allow init scripts to run
log "Removing initial setup barriers..."
sudo rm -f /var/lib/jenkins/secrets/initialAdminPassword
sudo rm -f /var/lib/jenkins/.setupwizard
sudo rm -f /var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion

# Set Jenkins Configuration as Code environment variable
log "Setting JCasC environment variable..."
if ! grep -q "CASC_JENKINS_CONFIG" /etc/default/jenkins; then
    echo 'CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yaml' | sudo tee -a /etc/default/jenkins >/dev/null
fi

# Set JAVA_OPTS to skip setup wizard
if ! grep -q "JENKINS_JAVA_OPTIONS.*-Djenkins.install.runSetupWizard=false" /etc/default/jenkins; then
    sudo sed -i 's|^JENKINS_JAVA_OPTIONS=.*|JENKINS_JAVA_OPTIONS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"|' /etc/default/jenkins
fi

# Reload systemd and start Jenkins
log "Starting Jenkins with new configuration..."
sudo systemctl daemon-reload
sudo systemctl start jenkins

# Wait for Jenkins to start
log "Waiting for Jenkins to start..."
for i in {1..30}; do
    if curl -s -f "http://localhost:8080/login" >/dev/null 2>&1; then
        log "Jenkins is running!"
        break
    fi
    sleep 5
done

# Check if Jenkins is accessible
if curl -s -f "http://localhost:8080/login" >/dev/null 2>&1; then
    log "✅ Jenkins is now accessible at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080/"
    log "✅ Login credentials: admin / admin123"
    log "✅ No setup wizard required!"
else
    err "Jenkins failed to start properly"
    exit 1
fi

log "Jenkins configuration fix completed!"
EOF

# Copy the script to the remote server and execute it
log "Copying configuration script to EC2 instance..."
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" /tmp/jenkins_setup.sh ubuntu@$EC2_IP:/tmp/

log "Executing Jenkins configuration fix on remote server..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@$EC2_IP "chmod +x /tmp/jenkins_setup.sh && sudo /tmp/jenkins_setup.sh"

log "Jenkins fix completed! You can now access Jenkins at:"
log "URL: http://$EC2_IP:8080/"
log "Username: admin"
log "Password: admin123"

# Clean up
rm -f /tmp/jenkins_setup.sh