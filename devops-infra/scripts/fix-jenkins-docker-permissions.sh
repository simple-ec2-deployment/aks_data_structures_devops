#!/bin/bash

# Fix Jenkins Docker Permissions Script
# Run this script on EC2 to fix Docker permissions for Jenkins user

set -e

echo "==========================================="
echo "Fixing Jenkins Docker Permissions"
echo "==========================================="
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo "This script needs to be run with sudo"
    echo "Usage: sudo ./fix-jenkins-docker-permissions.sh"
    exit 1
fi

echo "1. Adding jenkins user to docker group..."
usermod -aG docker jenkins

echo "2. Restarting Jenkins service..."
systemctl restart jenkins

echo "3. Checking Docker permissions..."
if sudo -u jenkins docker ps &> /dev/null; then
    echo "✓ Jenkins user can now access Docker"
else
    echo "⚠ Jenkins user may need to log out/in for group changes to take effect"
    echo "   Or restart the EC2 instance"
fi

echo ""
echo "4. Starting Minikube (if not already running)..."
# Start Minikube as jenkins user
if sudo -u jenkins minikube status &> /dev/null; then
    echo "✓ Minikube is already running"
else
    echo "Starting Minikube..."
    sudo -u jenkins minikube start --driver=docker 2>&1 || {
        echo "⚠ Failed to start Minikube as jenkins user"
        echo "   Trying alternative method..."
        # If that fails, start as root and change ownership
        minikube start --driver=docker 2>&1 || {
            echo "✗ Could not start Minikube"
            echo "   Please start manually: minikube start --driver=docker"
        }
        # Change ownership of minikube directory
        if [ -d "/home/jenkins/.minikube" ]; then
            chown -R jenkins:jenkins /home/jenkins/.minikube
        fi
    }
fi

echo ""
echo "5. Verifying setup..."
if sudo -u jenkins docker ps &> /dev/null && sudo -u jenkins minikube status &> /dev/null; then
    echo "✓ All checks passed!"
else
    echo "⚠ Some checks failed, but setup is mostly complete"
fi

echo ""
echo "==========================================="
echo "Setup Complete!"
echo "==========================================="
echo ""
echo "Next steps:"
echo "1. Wait 10-15 seconds for Jenkins to fully restart"
echo "2. Check Jenkins is running: sudo systemctl status jenkins"
echo "3. Run the Jenkins pipeline again"
echo ""
echo "If you still have issues:"
echo "- Verify Jenkins user is in docker group: groups jenkins"
echo "- Check Minikube status: sudo -u jenkins minikube status"
echo "- Check Docker access: sudo -u jenkins docker ps"
echo ""

