#!/bin/bash

# Jenkins Post-Installation Automation Script
# Run this AFTER Jenkins is working manually to add automation features
# This is a SAFE script that doesn't modify infrastructure setup

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { printf "${GREEN}[JENKINS-AUTO]${NC} %s\n" "$*"; }
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

# Configuration
EC2_IP=$(cd ../../aws-infrastrucutre-terraform/environments/dev && terraform output -raw ec2_public_ip 2>/dev/null || echo "")
SSH_KEY="../../aws-infrastrucutre-terraform/modules/ec2/keys/stack_key.pem"

if [ -z "$EC2_IP" ]; then
    err "Could not get EC2 IP. Make sure Terraform is deployed."
    exit 1
fi

log "Jenkins Post-Installation Automation for $EC2_IP"
info "This script adds automation features to an EXISTING working Jenkins"
info "Prerequisites:"
info "  ✅ Jenkins should already be working at http://$EC2_IP:8080/"
info "  ✅ You should have completed the setup wizard"
info "  ✅ Admin user should be created"
echo

read -p "Is Jenkins already working and set up? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    warn "Please set up Jenkins manually first, then run this script"
    exit 0
fi

# Create remote automation script
cat > /tmp/jenkins_post_install.sh << 'EOF'
#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { printf "${GREEN}[REMOTE]${NC} %s\n" "$*"; }
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

log "Starting Jenkins Post-Installation Automation"

# Check if Jenkins is running
if ! curl -s -f "http://localhost:8080/login" >/dev/null 2>&1; then
    err "Jenkins is not accessible. Please ensure it's running first."
    exit 1
fi

log "✅ Jenkins is accessible"

# Install additional plugins via Jenkins CLI
log "Installing automation plugins..."

# Download Jenkins CLI if not exists
JENKINS_CLI="/tmp/jenkins-cli.jar"
if [ ! -f "$JENKINS_CLI" ]; then
    log "Downloading jenkins-cli.jar..."
    curl -s "http://localhost:8080/jnlpJars/jenkins-cli.jar" -o "$JENKINS_CLI"
fi

# Get admin credentials (assuming standard admin user exists)
echo "Please provide Jenkins admin credentials:"
read -p "Admin username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

read -s -p "Admin password: " ADMIN_PASS
echo

# Test credentials
log "Testing admin credentials..."
if ! java -jar "$JENKINS_CLI" -s "http://localhost:8080/" -auth "$ADMIN_USER:$ADMIN_PASS" who-am-i >/dev/null 2>&1; then
    err "Invalid credentials or Jenkins not ready"
    exit 1
fi

log "✅ Credentials verified"

# Install essential automation plugins
AUTOMATION_PLUGINS=(
    "configuration-as-code"
    "job-dsl"
    "pipeline-stage-view"
    "blueocean"
    "role-strategy"
    "workflow-multibranch"
    "github-branch-source"
    "docker-workflow"
    "kubernetes"
)

log "Installing automation plugins..."
for plugin in "${AUTOMATION_PLUGINS[@]}"; do
    info "Installing $plugin..."
    java -jar "$JENKINS_CLI" -s "http://localhost:8080/" -auth "$ADMIN_USER:$ADMIN_PASS" install-plugin "$plugin" || warn "Failed to install $plugin"
done

log "Restarting Jenkins to load plugins..."
java -jar "$JENKINS_CLI" -s "http://localhost:8080/" -auth "$ADMIN_USER:$ADMIN_PASS" restart

# Wait for restart
log "Waiting for Jenkins to restart..."
sleep 30

# Wait for Jenkins to be ready
for i in {1..30}; do
    if curl -s -f "http://localhost:8080/login" >/dev/null 2>&1; then
        log "✅ Jenkins is back online"
        break
    fi
    sleep 5
done

# Set up JCasC configuration directory (optional)
log "Setting up Configuration as Code directory..."
sudo mkdir -p /var/lib/jenkins/casc_configs
sudo chown jenkins:jenkins /var/lib/jenkins/casc_configs

# Copy JCasC configuration if it exists
REPO_DIR="/home/ubuntu/aks_data_structures_devops"
if [ -f "$REPO_DIR/devops-infra/jenkins/jenkins-config/casc.yaml" ]; then
    info "Copying JCasC configuration..."
    sudo cp "$REPO_DIR/devops-infra/jenkins/jenkins-config/casc.yaml" /var/lib/jenkins/casc_configs/
    sudo chown jenkins:jenkins /var/lib/jenkins/casc_configs/casc.yaml
    
    # Set environment variable for JCasC (optional)
    sudo mkdir -p /etc/systemd/system/jenkins.service.d/
    sudo tee /etc/systemd/system/jenkins.service.d/casc.conf > /dev/null << 'CASCCONF'
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/casc.yaml"
CASCCONF
    
    info "JCasC configuration ready (reload Jenkins configuration to apply)"
else
    warn "JCasC configuration not found, skipping"
fi

# Create sample pipeline jobs via Job DSL
log "Creating sample pipeline jobs..."

# Create Job DSL script
JOBDSL_SCRIPT="/tmp/create_pipelines.groovy"
cat > "$JOBDSL_SCRIPT" << 'JOBDSL'
// Create AKS Platform folder
folder('AKS-Platform') {
    displayName('AKS Data Structures Platform')
    description('All pipelines for the AKS Data Structures project')
}

// Create Frontend Pipeline
pipelineJob('AKS-Platform/frontend-pipeline') {
    displayName('Frontend CI/CD Pipeline')
    description('Automated pipeline for React frontend')
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/simple-ec2-deployment/aks_data_structures_frontend.git')
                    }
                    branches('*/main')
                    scriptPath('Jenkinsfile')
                }
            }
        }
    }
}

// Create Backend Pipeline  
pipelineJob('AKS-Platform/backend-pipeline') {
    displayName('Backend CI/CD Pipeline')
    description('Automated pipeline for Python backend')
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/simple-ec2-deployment/aks_data_structures_backend.git')
                    }
                    branches('*/main')
                    scriptPath('Jenkinsfile')
                }
            }
        }
    }
}

// Create Infrastructure Pipeline
pipelineJob('AKS-Platform/infrastructure-pipeline') {
    displayName('Infrastructure Pipeline')
    description('Terraform infrastructure deployment')
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/simple-ec2-deployment/aks_data_structures_devops.git')
                    }
                    branches('*/main')
                    scriptPath('Jenkinsfile-EC2')
                }
            }
        }
    }
}
JOBDSL

# Execute Job DSL script
info "Creating pipelines via Job DSL..."
java -jar "$JENKINS_CLI" -s "http://localhost:8080/" -auth "$ADMIN_USER:$ADMIN_PASS" create-job "seed-job" << SEEDJOB
<?xml version='1.1' encoding='UTF-8'?>
<project>
    <description>Job DSL seed job for creating pipelines</description>
    <keepDependencies>false</keepDependencies>
    <properties/>
    <scm class="hudson.scm.NullSCM"/>
    <canRoam>true</canRoam>
    <disabled>false</disabled>
    <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
    <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
    <triggers/>
    <concurrentBuild>false</concurrentBuild>
    <builders>
        <javaposse.jobdsl.plugin.ExecuteDslScripts plugin="job-dsl">
            <scriptText>$(cat $JOBDSL_SCRIPT)</scriptText>
            <usingScriptText>true</usingScriptText>
            <sandbox>false</sandbox>
            <ignoreExisting>false</ignoreExisting>
            <ignoreMissingFiles>false</ignoreMissingFiles>
            <failOnMissingPlugin>false</failOnMissingPlugin>
            <unstableOnDeprecation>false</unstableOnDeprecation>
            <removedJobAction>IGNORE</removedJobAction>
            <removedViewAction>IGNORE</removedViewAction>
            <lookupStrategy>JENKINS_ROOT</lookupStrategy>
        </javaposse.jobdsl.plugin.ExecuteDslScripts>
    </builders>
    <publishers/>
    <buildWrappers/>
</project>
SEEDJOB

# Run the seed job
info "Running seed job to create pipelines..."
java -jar "$JENKINS_CLI" -s "http://localhost:8080/" -auth "$ADMIN_USER:$ADMIN_PASS" build "seed-job" -s

PUB_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

log "✅ Jenkins Post-Installation Automation Completed!"
log ""
log "🎯 What was added:"
log "  ✅ Configuration as Code plugin"
log "  ✅ Job DSL for automated pipeline creation"  
log "  ✅ Blue Ocean modern UI"
log "  ✅ Pipeline and workflow plugins"
log "  ✅ Sample pipelines in AKS-Platform folder"
log ""
log "🌐 Access your enhanced Jenkins:"
log "  📍 URL: http://$PUB_IP:8080/"
log "  👤 Login: $ADMIN_USER / [your password]"
log "  🎨 Try Blue Ocean: http://$PUB_IP:8080/blue/"
log ""
log "🚀 Jenkins is now automation-ready!"

EOF

# Execute the post-installation script
log "Copying post-installation script to EC2..."
scp -i "$SSH_KEY" /tmp/jenkins_post_install.sh ubuntu@$EC2_IP:/tmp/

log "Executing Jenkins post-installation automation..."
ssh -i "$SSH_KEY" -t ubuntu@$EC2_IP "chmod +x /tmp/jenkins_post_install.sh && /tmp/jenkins_post_install.sh"

log "🎉 Jenkins Post-Installation Automation Complete!"
info "Your Jenkins now has automation capabilities while keeping the infrastructure setup intact."

# Clean up
rm -f /tmp/jenkins_post_install.sh