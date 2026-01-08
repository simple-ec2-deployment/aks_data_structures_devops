# Jenkins Automated Setup

This directory contains configuration files for automatically setting up Jenkins with predefined admin credentials and recommended plugins.

## What This Setup Does

When you deploy your infrastructure using the `setup.sh` script, Jenkins will be automatically configured with:

### Admin User
- **Username**: `admin`
- **Password**: `admin123`
- **Email**: `admin@example.com`
- **Full Name**: `admin`

### Features
- Skips the initial setup wizard
- Automatically installs all recommended plugins
- Configures basic security settings
- Sets up Docker and Kubernetes integration
- Configures Git and GitHub integration

## Files

### Configuration Files

- `jenkins.yaml` - Jenkins Configuration as Code (JCasC) file
- `plugins.txt` - List of plugins to install automatically
- `init.groovy.d/01-basic-security.groovy` - Initial security setup script
- `init.groovy.d/02-install-plugins.groovy` - Plugin installation script
- `install-plugins.sh` - Shell script for plugin installation

### How It Works

1. **During Infrastructure Setup**: The `bootstrap.sh` script copies configuration files to Jenkins directories
2. **On Jenkins Start**: Init scripts run automatically to:
   - Create the admin user
   - Skip the setup wizard
   - Configure basic security
   - Install plugins
3. **Configuration as Code**: JCasC applies additional configuration settings

## Access Jenkins

After deployment, you can access Jenkins at:
```
http://YOUR_EC2_PUBLIC_IP:8080/
```

Login with:
- Username: `admin`
- Password: `admin123`

## Installed Plugins

The following plugins are automatically installed:

### Core Pipeline Plugins
- workflow-aggregator
- pipeline-stage-view
- pipeline-graph-view

### Git Integration
- git
- github
- github-branch-source
- github-pullrequest
- ssh-agent

### Credentials Management
- credentials
- credentials-binding
- ssh-credentials

### Docker Integration
- docker-workflow
- docker-plugin

### Kubernetes Integration
- kubernetes
- kubernetes-cli
- kubernetes-credentials-provider

### Build Tools
- gradle
- nodejs

### Testing & Quality
- junit
- cobertura
- htmlpublisher

### Notifications
- slack
- email-ext

### Utilities
- timestamper
- ansicolor
- rebuild
- build-timeout
- ws-cleanup

### Security
- role-strategy

### Configuration as Code
- configuration-as-code
- job-dsl

## Customization

To customize the setup:

1. **Modify Admin Credentials**: Edit `jenkins.yaml` and `01-basic-security.groovy`
2. **Add/Remove Plugins**: Update `plugins.txt`
3. **Change Configuration**: Modify `jenkins.yaml` for JCasC settings

## Security Notes

⚠️ **Important**: The default credentials (`admin/admin123`) are for development/testing only. For production use:

1. Change the default password immediately after first login
2. Configure proper authentication (LDAP, OAuth, etc.)
3. Set up role-based access control
4. Enable CSRF protection and other security features

## Troubleshooting

### Jenkins Won't Start
- Check logs: `sudo journalctl -u jenkins -f`
- Verify Java installation: `java -version`
- Check Jenkins status: `sudo systemctl status jenkins`

### Plugins Not Installing
- Check Jenkins logs: `sudo tail -f /var/log/jenkins/jenkins.log`
- Verify internet connectivity
- Try manual installation via Jenkins UI

### Configuration Not Applied
- Ensure files are in correct locations:
  - `/var/lib/jenkins/casc_configs/jenkins.yaml`
  - `/var/lib/jenkins/init.groovy.d/*.groovy`
- Check file ownership: `sudo chown -R jenkins:jenkins /var/lib/jenkins/`

### Access Issues
- Verify AWS Security Group allows port 8080
- Check if Jenkins is listening: `sudo netstat -tlnp | grep 8080`
- Test local access: `curl http://localhost:8080/login`

## Manual Setup Alternative

If automated setup fails, you can still set up Jenkins manually:

1. Access Jenkins at `http://YOUR_IP:8080/`
2. Use initial admin password: `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`
3. Install suggested plugins
4. Create admin user manually

## References

- [Jenkins Configuration as Code](https://github.com/jenkinsci/configuration-as-code-plugin)
- [Jenkins Init Scripts](https://wiki.jenkins.io/display/JENKINS/Post-initialization+script)
- [Jenkins Plugin Installation](https://wiki.jenkins.io/display/JENKINS/Plugin+tutorial)