#!/bin/bash

# Final Jenkins Fix Script - This will properly set up admin user

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { printf "${GREEN}[JENKINS-FINAL-FIX]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

EC2_IP=$(cd aws-infrastrucutre-terraform/environments/dev && terraform output -raw ec2_public_ip)
SSH_KEY="aws-infrastrucutre-terraform/modules/ec2/keys/stack_key.pem"

log "Final Jenkins fix for EC2 instance at $EC2_IP"

# Create the comprehensive fix script
cat > /tmp/jenkins_final_fix.sh << 'EOF'
#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m'
log() { printf "${GREEN}[REMOTE]${NC} %s\n" "$*"; }

log "Starting final Jenkins configuration fix..."

# Stop Jenkins
sudo systemctl stop jenkins

# Clean everything and start fresh
sudo rm -rf /var/lib/jenkins/users/*
sudo rm -f /var/lib/jenkins/secrets/initialAdminPassword
sudo rm -f /var/lib/jenkins/.setupwizard
sudo rm -f /var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion

# Create proper users.xml mapping first
sudo tee /var/lib/jenkins/users/users.xml > /dev/null << 'USERSXML'
<?xml version='1.1' encoding='UTF-8'?>
<hudson.model.UserIdMapper>
  <version>1</version>
  <idToDirectoryNameMap class="concurrent-hash-map">
    <entry>
      <string>admin</string>
      <string>admin_74525d72e9da74f1f7a866736010aa3e3178589b9afb5bb440bb647293840264</string>
    </entry>
  </idToDirectoryNameMap>
</hudson.model.UserIdMapper>
USERSXML

# Create admin user directory with the exact name Jenkins expects
sudo mkdir -p /var/lib/jenkins/users/admin_74525d72e9da74f1f7a866736010aa3e3178589b9afb5bb440bb647293840264

# Create admin user config with proper password hash for 'admin123'
sudo tee /var/lib/jenkins/users/admin_74525d72e9da74f1f7a866736010aa3e3178589b9afb5bb440bb647293840264/config.xml > /dev/null << 'USERXML'
<?xml version='1.1' encoding='UTF-8'?>
<user>
  <version>1</version>
  <id>admin</id>
  <fullName>admin</fullName>
  <description></description>
  <properties>
    <hudson.security.HudsonPrivateSecurityRealm_-Details>
      <passwordHash>#jbcrypt:$2a$10$MiTkNhZlSUJTU/2EG3NbnOZDUw98KA6AOMiGn3Q/MJgwTkk5OsOv6</passwordHash>
    </hudson.security.HudsonPrivateSecurityRealm_-Details>
    <hudson.model.MyViewsProperty>
      <viewsTabBar class="hudson.views.DefaultViewsTabBar"/>
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
    <hudson.model.TimeZoneProperty/>
    <hudson.search.UserSearchProperty>
      <insensitiveSearch>true</insensitiveSearch>
    </hudson.search.UserSearchProperty>
    <hudson.model.PaneStatusProperties>
      <collapsed/>
    </hudson.model.PaneStatusProperties>
    <jenkins.security.seed.UserSeedProperty>
      <seed>74525d72e9da74f1f7a866736010aa3e3178589b9afb5bb440bb647293840264</seed>
    </jenkins.security.seed.UserSeedProperty>
  </properties>
</user>
USERXML

# Update main Jenkins config to disable CSRF temporarily and ensure proper security
sudo tee /var/lib/jenkins/config.xml > /dev/null << 'CONFIGXML'
<?xml version='1.1' encoding='UTF-8'?>
<hudson>
  <disabledAdministrativeMonitors/>
  <version>2.528.3</version>
  <installStateName>INITIAL_SETUP_COMPLETED</installStateName>
  <numExecutors>2</numExecutors>
  <mode>NORMAL</mode>
  <useSecurity>true</useSecurity>
  <authorizationStrategy class="hudson.security.FullControlOnceLoggedInAuthorizationStrategy">
    <denyAnonymousReadAccess>false</denyAnonymousReadAccess>
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
  <label></label>
  <nodeProperties/>
  <globalNodeProperties/>
  <nodeRenameMigrationNeeded>false</nodeRenameMigrationNeeded>
</hudson>
CONFIGXML

# Set proper ownership
sudo chown -R jenkins:jenkins /var/lib/jenkins/

# Ensure JAVA_OPTS skip setup wizard
sudo sed -i 's|^JENKINS_JAVA_OPTIONS=.*|JENKINS_JAVA_OPTIONS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"|' /etc/default/jenkins

# Start Jenkins
log "Starting Jenkins with fixed configuration..."
sudo systemctl daemon-reload
sudo systemctl start jenkins

# Wait for Jenkins to start
log "Waiting for Jenkins to start..."
for i in {1..60}; do
    if curl -s -f "http://localhost:8080/login" >/dev/null 2>&1; then
        log "Jenkins is running!"
        break
    fi
    sleep 2
done

# Test login
log "Testing admin login..."
PUB_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Get cookies and crumb
COOKIE_JAR="/tmp/jenkins_cookies.txt"
curl -c "$COOKIE_JAR" "http://localhost:8080/login" >/dev/null 2>&1

# Try login
LOGIN_RESULT=$(curl -b "$COOKIE_JAR" -c "$COOKIE_JAR" -s -o /dev/null -w "%{http_code}" \
    -d "j_username=admin&j_password=admin123&remember_me=on&from=&Submit=Sign+in" \
    -X POST "http://localhost:8080/j_spring_security_check")

if [ "$LOGIN_RESULT" = "302" ]; then
    # Check redirect location
    REDIRECT_LOCATION=$(curl -b "$COOKIE_JAR" -s -I \
        -d "j_username=admin&j_password=admin123&remember_me=on&from=&Submit=Sign+in" \
        -X POST "http://localhost:8080/j_spring_security_check" | grep -i location | cut -d' ' -f2 | tr -d '\r')
    
    if [[ "$REDIRECT_LOCATION" == *"/loginError"* ]]; then
        log "❌ Login still failed - password incorrect"
    else
        log "✅ Login successful!"
        log "✅ Jenkins URL: http://$PUB_IP:8080/"
        log "✅ Username: admin"
        log "✅ Password: admin123"
    fi
else
    log "❌ Login failed with status code: $LOGIN_RESULT"
fi

rm -f "$COOKIE_JAR"

log "Jenkins configuration completed!"
EOF

# Execute the fix
log "Copying final fix script to EC2..."
scp -i "$SSH_KEY" /tmp/jenkins_final_fix.sh ubuntu@$EC2_IP:/tmp/

log "Executing final Jenkins fix..."
ssh -i "$SSH_KEY" ubuntu@$EC2_IP "chmod +x /tmp/jenkins_final_fix.sh && sudo /tmp/jenkins_final_fix.sh"

log "Final fix completed!"
log "Try logging in at: http://$EC2_IP:8080/"
log "Username: admin"
log "Password: admin123"

# Clean up
rm -f /tmp/jenkins_final_fix.sh