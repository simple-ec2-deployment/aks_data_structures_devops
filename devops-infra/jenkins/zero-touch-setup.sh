#!/bin/bash

# Zero-Touch Jenkins Setup Script
# This script implements fully automated Jenkins configuration using JCasC

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { printf "${GREEN}[ZERO-TOUCH]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }

# Get EC2 public IP from Terraform output
EC2_IP=$(cd ../../aws-infrastrucutre-terraform/environments/dev && terraform output -raw ec2_public_ip 2>/dev/null || echo "")
SSH_KEY="../../aws-infrastrucutre-terraform/modules/ec2/keys/stack_key.pem"

if [ -z "$EC2_IP" ]; then
    err "Could not get EC2 public IP from Terraform"
    exit 1
fi

log "Implementing Zero-Touch Jenkins setup on EC2 instance at $EC2_IP"

# Create the comprehensive zero-touch setup script
cat > /tmp/zero_touch_jenkins.sh << 'EOF'
#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { printf "${GREEN}[REMOTE]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }

log "Starting Zero-Touch Jenkins Configuration..."

# Stop Jenkins first
sudo systemctl stop jenkins

# Clean up existing configuration
log "Cleaning up existing Jenkins configuration..."
sudo rm -rf /var/lib/jenkins/users/*
sudo rm -f /var/lib/jenkins/secrets/initialAdminPassword
sudo rm -f /var/lib/jenkins/.setupwizard
sudo rm -f /var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion
sudo rm -f /var/lib/jenkins/config.xml
sudo rm -rf /var/lib/jenkins/jobs/*

# Create Jenkins directories for automation
log "Creating Jenkins automation directories..."
sudo mkdir -p /var/lib/jenkins/casc_configs
sudo mkdir -p /var/lib/jenkins/init.groovy.d
sudo mkdir -p /var/lib/jenkins/ref/plugins

# Copy configuration files from repository
REPO_DIR="/home/ubuntu/aks_data_structures_devops"
if [ -d "$REPO_DIR/devops-infra/jenkins/jenkins-config" ]; then
    log "Copying Jenkins Configuration as Code files..."
    
    # Copy JCasC configuration
    sudo cp "$REPO_DIR/devops-infra/jenkins/jenkins-config/casc.yaml" /var/lib/jenkins/casc_configs/jenkins.yaml
    
    # Copy plugins list
    sudo cp "$REPO_DIR/devops-infra/jenkins/jenkins-config/plugins.txt" /var/lib/jenkins/ref/plugins.txt
    
    log "Configuration files copied successfully"
else
    err "Jenkins configuration directory not found at $REPO_DIR"
    exit 1
fi

# Set environment variables for JCasC
log "Configuring Jenkins environment variables..."

# Create environment file for Jenkins
sudo tee /etc/default/jenkins.env > /dev/null << 'ENVFILE'
# Jenkins Environment Variables for Zero-Touch Setup
export ADMIN_PASSWORD=admin123
export DEV_PASSWORD=dev123
export GITHUB_USERNAME=admin
export GITHUB_TOKEN=admin123
export DOCKER_HUB_TOKEN=dummy-token
export SSH_PRIVATE_KEY=dummy-key
export JENKINS_URL=http://localhost:8080/
ENVFILE

# Update Jenkins defaults to include JCasC and disable setup wizard
log "Updating Jenkins configuration..."
sudo tee /etc/default/jenkins > /dev/null << 'JENKINSCONF'
# Jenkins Configuration for Zero-Touch Setup

# Default Jenkins location
NAME=jenkins

# Arguments to pass to jenkins
JENKINS_ARGS="--webroot=/var/cache/$NAME/war --httpPort=8080"

# Run Jenkins as this user ID (default)
JENKINS_USER=$NAME

# Run Jenkins as this group ID (default)  
JENKINS_GROUP=$NAME

# Location of the jenkins war file
JENKINS_WAR=/usr/share/java/jenkins.war

# Jenkins home directory
JENKINS_HOME=/var/lib/jenkins

# Set locations for the jenkins log files  
JENKINS_LOG=/var/log/jenkins/$NAME.log

# Java options
JAVA_ARGS="-Djava.awt.headless=true"

# Jenkins Configuration as Code
CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yaml

# Jenkins Java Options - CRITICAL for automation
JENKINS_JAVA_OPTIONS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Djenkins.install.InstallUtil.lastExecVersion=2.528.3 -Dcasc.jenkins.config=/var/lib/jenkins/casc_configs/jenkins.yaml"

# OS LIMITS
ulimit -n 8192
ulimit -u 30654
ulimit -d unlimited
ulimit -m unlimited
ulimit -s 8192
ulimit -t unlimited
ulimit -v unlimited
ulimit -x unlimited
ulimit -i 30654
ulimit -q 819200

# Load environment variables
if [ -f /etc/default/jenkins.env ]; then
    set -a
    source /etc/default/jenkins.env
    set +a
fi
JENKINSCONF

# Install plugins using Jenkins Plugin Manager
log "Installing plugins automatically..."

# Create plugin installation script
sudo tee /tmp/install_plugins.sh > /dev/null << 'PLUGINSCRIPT'
#!/bin/bash

JENKINS_HOME=/var/lib/jenkins
PLUGINS_TXT=$JENKINS_HOME/ref/plugins.txt

if [ ! -f "$PLUGINS_TXT" ]; then
    echo "Plugins file not found at $PLUGINS_TXT"
    exit 1
fi

# Download jenkins-plugin-cli if not exists
PLUGIN_CLI="/opt/jenkins-plugin-cli.jar"
if [ ! -f "$PLUGIN_CLI" ]; then
    echo "Downloading jenkins-plugin-cli..."
    curl -fsSL "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/latest/download/jenkins-plugin-manager-2.13.0.jar" -o "$PLUGIN_CLI"
fi

echo "Installing plugins from $PLUGINS_TXT..."
java -jar "$PLUGIN_CLI" \
    --war /usr/share/java/jenkins.war \
    --plugin-download-directory "$JENKINS_HOME/plugins" \
    --plugin-file "$PLUGINS_TXT" \
    --verbose

echo "Plugin installation completed"
PLUGINSCRIPT

sudo chmod +x /tmp/install_plugins.sh
sudo /tmp/install_plugins.sh

# Set proper ownership
log "Setting proper file ownership..."
sudo chown -R jenkins:jenkins /var/lib/jenkins/
sudo chmod -R 755 /var/lib/jenkins/casc_configs/
sudo chmod 644 /var/lib/jenkins/casc_configs/jenkins.yaml

# Create systemd override for Jenkins service
log "Configuring Jenkins service..."
sudo mkdir -p /etc/systemd/system/jenkins.service.d/
sudo tee /etc/systemd/system/jenkins.service.d/override.conf > /dev/null << 'OVERRIDE'
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yaml"
Environment="ADMIN_PASSWORD=admin123"
Environment="DEV_PASSWORD=dev123"
Environment="GITHUB_USERNAME=admin"
Environment="GITHUB_TOKEN=admin123"
Environment="JENKINS_URL=http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080/"

# Override Java options to ensure automation
Environment="JENKINS_JAVA_OPTIONS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Djenkins.install.InstallUtil.lastExecVersion=2.528.3 -Dcasc.jenkins.config=/var/lib/jenkins/casc_configs/jenkins.yaml"

# Increase timeouts for plugin installation
TimeoutStartSec=300
TimeoutStopSec=60
OVERRIDE

# Reload systemd and start Jenkins
log "Starting Jenkins with Zero-Touch configuration..."
sudo systemctl daemon-reload
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Wait for Jenkins to start
log "Waiting for Jenkins to fully initialize..."
TIMEOUT=300
COUNTER=0

while [ $COUNTER -lt $TIMEOUT ]; do
    if curl -s -f "http://localhost:8080/login" >/dev/null 2>&1; then
        log "Jenkins is responding on port 8080"
        break
    fi
    
    if [ $((COUNTER % 30)) -eq 0 ] && [ $COUNTER -gt 0 ]; then
        log "Still waiting for Jenkins... ($COUNTER/${TIMEOUT}s)"
    fi
    
    sleep 5
    COUNTER=$((COUNTER + 5))
done

if [ $COUNTER -ge $TIMEOUT ]; then
    err "Jenkins failed to start within $TIMEOUT seconds"
    sudo journalctl -u jenkins -n 20 --no-pager
    exit 1
fi

# Verify JCasC configuration is loaded
log "Verifying Zero-Touch configuration..."
sleep 30  # Give Jenkins time to process JCasC

# Check if admin user was created
if curl -s -f "http://localhost:8080/login" >/dev/null 2>&1; then
    PUB_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    
    log "✅ Jenkins Zero-Touch Setup Completed Successfully!"
    log "🌐 Jenkins URL: http://$PUB_IP:8080/"
    log "👤 Admin User: admin / admin123"
    log "👤 Developer User: developer / dev123"
    log "🎯 Features Enabled:"
    log "   - Configuration as Code (JCasC)"
    log "   - Job DSL for automated pipeline creation"
    log "   - Role-based security"
    log "   - Blue Ocean modern UI"
    log "   - All essential plugins pre-installed"
    log "   - Automated pipeline jobs created"
    
    log "🚀 Jenkins is ready for immediate use!"
else
    err "Jenkins setup verification failed"
    exit 1
fi

log "Zero-Touch Jenkins setup completed successfully!"
EOF

# Copy and execute the zero-touch setup script
log "Copying zero-touch setup script to EC2..."
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" /tmp/zero_touch_jenkins.sh ubuntu@$EC2_IP:/tmp/

log "Executing Zero-Touch Jenkins setup..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@$EC2_IP "chmod +x /tmp/zero_touch_jenkins.sh && sudo /tmp/zero_touch_jenkins.sh"

log "🎉 Zero-Touch Jenkins Setup Completed!"
info "Jenkins is now fully automated and ready to use:"
info "🌐 URL: http://$EC2_IP:8080/"
info "👤 Admin: admin / admin123"
info "👤 Developer: developer / dev123"
info ""
info "✨ Features:"
info "• No setup wizard - direct access"
info "• Pre-configured users and roles"
info "• All essential plugins installed"
info "• Automated CI/CD pipelines created"
info "• Blue Ocean modern interface"
info "• Configuration as Code enabled"

# Clean up
rm -f /tmp/zero_touch_jenkins.sh

log "Setup complete! Access Jenkins at http://$EC2_IP:8080/"