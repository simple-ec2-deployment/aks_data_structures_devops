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
echo "4. Checking Minikube status..."
if sudo -u jenkins minikube status &> /dev/null; then
    echo "✓ Minikube is accessible"
else
    echo "⚠ Minikube may need to be started"
    echo "   Run: sudo -u jenkins minikube start"
fi

echo ""
echo "==========================================="
echo "Setup Complete!"
echo "==========================================="
echo ""
echo "Next steps:"
echo "1. Wait a few seconds for Jenkins to restart"
echo "2. Run the Jenkins pipeline again"
echo ""

