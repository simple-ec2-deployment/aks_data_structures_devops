#!/bin/bash

# Simple Jenkins Plugin Installer and Configuration Script

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { printf "${GREEN}[INSTALL]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

EC2_IP=$(cd aws-infrastrucutre-terraform/environments/dev && terraform output -raw ec2_public_ip)
SSH_KEY="aws-infrastrucutre-terraform/modules/ec2/keys/stack_key.pem"

log "Installing Jenkins plugins and configuring zero-touch setup on $EC2_IP"

# Create simple installation script
cat > /tmp/simple_jenkins_setup.sh << 'EOF'
#!/bin/bash

set -euo pipefail

log() { printf "\033[0;32m[REMOTE]\033[0m %s\n" "$*"; }

log "Starting simple Jenkins plugin installation and configuration"

# Stop Jenkins
sudo systemctl stop jenkins

# Install plugins manually using jenkins-cli.jar
log "Installing essential plugins using Jenkins CLI"

# Wait for Jenkins to be ready for CLI
sudo systemctl start jenkins
sleep 30

# Download jenkins-cli.jar
JENKINS_CLI="/tmp/jenkins-cli.jar"
curl -s "http://localhost:8080/jnlpJars/jenkins-cli.jar" -o "$JENKINS_CLI"

# Get initial admin password
INITIAL_PASSWORD=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)

# Install critical plugins one by one
CRITICAL_PLUGINS=(
    "configuration-as-code"
    "job-dsl" 
    "workflow-aggregator"
    "git"
    "credentials"
    "role-strategy"
)

log "Installing critical plugins with initial admin password"
for plugin in "${CRITICAL_PLUGINS[@]}"; do
    log "Installing $plugin..."
    java -jar "$JENKINS_CLI" -s "http://localhost:8080/" -auth "admin:$INITIAL_PASSWORD" install-plugin "$plugin" || log "Failed to install $plugin (may already exist)"
done

# Restart Jenkins to load plugins
log "Restarting Jenkins to load plugins"
sudo systemctl restart jenkins
sleep 30

# Now apply JCasC configuration
log "Applying Configuration as Code"
sudo mkdir -p /var/lib/jenkins/casc_configs
sudo cp /home/ubuntu/aks_data_structures_devops/devops-infra/jenkins/jenkins-config/casc.yaml /var/lib/jenkins/casc_configs/jenkins.yaml
sudo chown jenkins:jenkins /var/lib/jenkins/casc_configs/jenkins.yaml

# Update Jenkins environment to use JCasC
sudo tee /etc/systemd/system/jenkins.service.d/override.conf > /dev/null << 'ENVCONF'
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yaml"
Environment="ADMIN_PASSWORD=admin123"
Environment="DEV_PASSWORD=dev123"
Environment="JENKINS_JAVA_OPTIONS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Dcasc.jenkins.config=/var/lib/jenkins/casc_configs/jenkins.yaml"
ENVCONF

# Reload and restart Jenkins
log "Restarting Jenkins with JCasC configuration"
sudo systemctl daemon-reload
sudo systemctl restart jenkins

# Wait for restart
sleep 45

# Test access
if curl -s -f "http://localhost:8080/login" >/dev/null 2>&1; then
    PUB_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    log "✅ Jenkins configured successfully!"
    log "🌐 URL: http://$PUB_IP:8080/"
    log "👤 Try logging in with: admin / admin123"
    log "👤 If that doesn't work, use initial password: $INITIAL_PASSWORD"
else
    log "❌ Jenkins setup may have issues"
fi

log "Jenkins setup completed"
EOF

# Execute the setup
log "Copying and executing simple Jenkins setup"
scp -i "$SSH_KEY" /tmp/simple_jenkins_setup.sh ubuntu@$EC2_IP:/tmp/
ssh -i "$SSH_KEY" ubuntu@$EC2_IP "chmod +x /tmp/simple_jenkins_setup.sh && sudo /tmp/simple_jenkins_setup.sh"

log "Setup completed! Try accessing Jenkins at http://$EC2_IP:8080/"
log "Login with admin/admin123 or use the initial admin password if needed"

# Clean up
rm -f /tmp/simple_jenkins_setup.sh