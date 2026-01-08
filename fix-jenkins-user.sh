#!/bin/bash

# Create Jenkins Admin User Script
# This script will create the admin user manually using Jenkins CLI

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() { printf "${GREEN}[JENKINS-USER-FIX]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

# Get EC2 public IP from Terraform output
EC2_IP=$(cd aws-infrastrucutre-terraform/environments/dev && terraform output -raw ec2_public_ip)
SSH_KEY="aws-infrastrucutre-terraform/modules/ec2/keys/stack_key.pem"

if [ -z "$EC2_IP" ]; then
    err "Could not get EC2 public IP"
    exit 1
fi

log "Fixing Jenkins admin user on EC2 instance at $EC2_IP"

# Create the Jenkins user creation script
cat > /tmp/jenkins_user_setup.sh << 'EOF'
#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { printf "${GREEN}[REMOTE]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

log "Starting Jenkins admin user creation..."

# Stop Jenkins first
sudo systemctl stop jenkins

# Remove existing config to start fresh
sudo rm -rf /var/lib/jenkins/users/admin*
sudo rm -f /var/lib/jenkins/secrets/initialAdminPassword
sudo rm -f /var/lib/jenkins/.setupwizard
sudo rm -f /var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion
sudo rm -f /var/lib/jenkins/config.xml

# Create basic Jenkins config.xml
sudo tee /var/lib/jenkins/config.xml > /dev/null << 'CONFIGXML'
<?xml version='1.1' encoding='UTF-8'?>
<hudson>
  <disabledAdministrativeMonitors/>
  <version>2.440.3</version>
  <installStateName>INITIAL_SETUP_COMPLETED</installStateName>
  <numExecutors>2</numExecutors>
  <mode>NORMAL</mode>
  <useSecurity>true</useSecurity>
  <authorizationStrategy class="hudson.security.FullControlOnceLoggedInAuthorizationStrategy">
    <denyAnonymousReadAccess>true</denyAnonymousReadAccess>
  </authorizationStrategy>
  <securityRealm class="hudson.security.HudsonPrivateSecurityRealm">
    <disableSignup>true</disableSignup>
    <enableCaptcha>false</enableCaptcha>
  </securityRealm>
  <disableRememberMe>false</disableRememberMe>
  <projectNamingStrategy class="jenkins.model.ProjectNamingStrategy$DefaultProjectNamingStrategy"/>
  <workspaceDir>${JENKINS_HOME}/workspace/${ITEM_FULLNAME}</workspaceDir>
  <buildsDir>${ITEM_ROOTDIR}/builds</buildsDir>
  <markupFormatter class="hudson.markup.EscapedMarkupFormatter"/>
  <jdks/>
  <viewsTabBar class="hudson.views.DefaultViewsTabBar"/>
  <myViewsTabBar class="hudson.views.DefaultMyViewsTabBar"/>
  <clouds/>
  <scmCheckoutRetryCount>0</scmCheckoutRetryCount>
  <views>
    <hudson.model.AllView>
      <owner class="hudson" reference="../../.."/>
      <name>all</name>
      <filterExecutors>false</filterExecutors>
      <filterQueue>false</filterQueue>
      <properties class="hudson.model.View$PropertyList"/>
    </hudson.model.AllView>
  </views>
  <primaryView>all</primaryView>
  <slaveAgentPort>-1</slaveAgentPort>
  <nodeProperties/>
  <globalNodeProperties/>
</hudson>
CONFIGXML

# Create admin user directory and config
sudo mkdir -p /var/lib/jenkins/users/admin_1234567890123456789

# Create admin user config (password hash for 'admin123')
sudo tee /var/lib/jenkins/users/admin_1234567890123456789/config.xml > /dev/null << 'USERXML'
<?xml version='1.1' encoding='UTF-8'?>
<user>
  <fullName>admin</fullName>
  <description></description>
  <properties>
    <hudson.security.HudsonPrivateSecurityRealm_-Details>
      <passwordHash>#jbcrypt:$2a$10$MiTkNhZlSUJTU/2EG3NbnOZDUw98KA6AOMiGn3Q/MJgwTkk5OsOv6</passwordHash>
    </hudson.security.HudsonPrivateSecurityRealm_-Details>
    <hudson.model.MyViewsProperty>
      <views>
        <hudson.model.AllView>
          <owner class="hudson.model.MyViewsProperty" reference="../../.."/>
          <name>all</name>
          <filterExecutors>false</filterExecutors>
          <filterQueue>false</filterQueue>
          <properties class="hudson.model.View$PropertyList"/>
        </hudson.model.AllView>
      </views>
    </hudson.model.MyViewsProperty>
    <org.jenkinsci.plugins.displayurlapi.user.PreferredProviderUserProperty plugin="display-url-api@2.3.5">
      <providerId>default</providerId>
    </org.jenkinsci.plugins.displayurlapi.user.PreferredProviderUserProperty>
    <hudson.model.PaneStatusProperties>
      <collapsed/>
    </hudson.model.PaneStatusProperties>
    <jenkins.security.seed.UserSeedProperty>
      <seed>1234567890123456789</seed>
    </jenkins.security.seed.UserSeedProperty>
    <hudson.search.UserSearchProperty>
      <insensitiveSearch>true</insensitiveSearch>
    </hudson.search.UserSearchProperty>
    <hudson.model.TimeZoneProperty/>
    <hudson.security.HudsonPrivateSecurityRealm_-Details>
      <passwordHash>#jbcrypt:$2a$10$MiTkNhZlSUJTU/2EG3NbnOZDUw98KA6AOMiGn3Q/MJgwTkk5OsOv6</passwordHash>
    </hudson.security.HudsonPrivateSecurityRealm_-Details>
  </properties>
</user>
USERXML

# Create users.xml to register the admin user
sudo tee /var/lib/jenkins/users/users.xml > /dev/null << 'USERSXML'
<?xml version='1.1' encoding='UTF-8'?>
<hudson.model.UserIdMapper>
  <version>1</version>
  <idToDirectoryNameMap class="concurrent-hash-map">
    <entry>
      <string>admin</string>
      <string>admin_1234567890123456789</string>
    </entry>
  </idToDirectoryNameMap>
</hudson.model.UserIdMapper>
USERSXML

# Set proper ownership
sudo chown -R jenkins:jenkins /var/lib/jenkins/

# Set JAVA_OPTS to skip setup wizard
sudo sed -i 's|^JENKINS_JAVA_OPTIONS=.*|JENKINS_JAVA_OPTIONS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"|' /etc/default/jenkins

# Start Jenkins
log "Starting Jenkins with admin user..."
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

# Test login
PUB_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
if curl -s -f "http://localhost:8080/login" >/dev/null 2>&1; then
    log "✅ Jenkins is accessible at http://$PUB_IP:8080/"
    log "✅ Login: admin / admin123"
    log "✅ Admin user created successfully!"
else
    err "Jenkins failed to start"
    exit 1
fi

log "Jenkins admin user setup completed!"
EOF

# Copy and execute the script
log "Copying user creation script to EC2 instance..."
scp -i "$SSH_KEY" /tmp/jenkins_user_setup.sh ubuntu@$EC2_IP:/tmp/

log "Creating Jenkins admin user..."
ssh -i "$SSH_KEY" ubuntu@$EC2_IP "chmod +x /tmp/jenkins_user_setup.sh && sudo /tmp/jenkins_user_setup.sh"

log "Jenkins admin user fix completed!"
log "URL: http://$EC2_IP:8080/"
log "Username: admin"
log "Password: admin123"

# Clean up
rm -f /tmp/jenkins_user_setup.sh