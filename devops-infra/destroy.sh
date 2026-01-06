#!/bin/bash

# DevOps Infrastructure Destroy Script
# Complete cleanup script for AKS Data Structures Platform
# This script removes all Kubernetes resources and cleans up the environment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
ENVIRONMENT="${1:-dev}"
REMOVE_IMAGES="${2:-true}"
CLEAN_ALL="${3:-false}"

echo -e "${RED}========================================${NC}"
echo -e "${RED}  AKS Data Structures - DevOps Cleanup${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Remove Docker Images: $REMOVE_IMAGES"
echo "Clean All Resources: $CLEAN_ALL"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo ""
    echo -e "${RED}=== $1 ===${NC}"
    echo ""
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if we're on EC2
if [ -f /etc/cloud/cloud-init.disabled ] || [ -d /home/ubuntu ]; then
    EC2_ENV=true
    print_status "Detected EC2 environment"
else
    EC2_ENV=false
fi

# Warning and confirmation
print_header "⚠️  WARNING: This will delete all deployed resources!"

echo "This script will permanently delete:"
echo "  - All Kubernetes deployments, services, and ingress"
echo "  - All ConfigMaps and Secrets"
echo "  - Monitoring stack (Prometheus, Grafana)"
echo "  - Docker images (if requested)"
echo "  - Port-forward services"
echo "  - Log files and temporary data"
echo ""

if [ "$CLEAN_ALL" = "true" ]; then
    echo -e "${RED}CLEAN ALL MODE: This will also remove:${NC}"
    echo "  - All Docker images and containers"
    echo "  - Minikube cluster (if using Minikube)"
    echo "  - Kubernetes configuration"
    echo "  - All generated files"
    echo ""
fi

read -p "Are you sure you want to continue? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    print_warning "Cleanup cancelled by user"
    exit 0
fi

# Stop port-forward services
print_header "Step 1: Stopping Port-Forward Services"

if [ "$EC2_ENV" = true ]; then
    # Stop systemd service
    if sudo systemctl is-active --quiet k8s-port-forward.service 2>/dev/null; then
        echo "Stopping port-forward systemd service..."
        sudo systemctl stop k8s-port-forward.service
        sudo systemctl disable k8s-port-forward.service
        print_status "Port-forward service stopped and disabled"
    fi
    
    # Remove service file
    if [ -f /etc/systemd/system/k8s-port-forward.service ]; then
        sudo rm -f /etc/systemd/system/k8s-port-forward.service
        sudo systemctl daemon-reload
        print_status "Port-forward service file removed"
    fi
else
    # Kill background port-forward processes
    if [ -f /tmp/k8s-port-forward.pid ]; then
        PID=$(cat /tmp/k8s-port-forward.pid)
        if kill -0 "$PID" 2>/dev/null; then
            echo "Stopping port-forward process (PID: $PID)..."
            kill "$PID"
            print_status "Port-forward process stopped"
        fi
        rm -f /tmp/k8s-port-forward.pid
    fi
    
    # Kill any remaining port-forward processes
    pkill -f 'kubectl port-forward' || true
    print_status "All port-forward processes killed"
fi

# Remove Kubernetes resources
print_header "Step 2: Removing Kubernetes Resources"

DEVOPS_INFRA="$PROJECT_ROOT/devops-infra"

# Check kubectl connection
if ! kubectl cluster-info >/dev/null 2>&1; then
    print_warning "Cannot connect to Kubernetes cluster"
    print_warning "Skipping Kubernetes resource cleanup"
else
    print_status "Connected to Kubernetes cluster"
    
    # Remove monitoring stack first
    echo "Removing monitoring stack..."
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        kubectl delete namespace monitoring --ignore-not-found=true --timeout=60s || true
        print_status "Monitoring namespace deleted"
    fi
    
    # Remove application resources
    echo "Removing application resources..."
    
    # Delete ingress
    kubectl delete ingress ingress-nginx --ignore-not-found=true --timeout=30s || true
    
    # Delete deployments
    kubectl delete deployment frontend-deployment --ignore-not-found=true --timeout=30s || true
    kubectl delete deployment backend-deployment --ignore-not-found=true --timeout=30s || true
    kubectl delete deployment stack-deployment --ignore-not-found=true --timeout=30s || true
    kubectl delete deployment linkedlist-deployment --ignore-not-found=true --timeout=30s || true
    kubectl delete deployment graph-deployment --ignore-not-found=true --timeout=30s || true
    
    # Delete services
    kubectl delete service frontend-service --ignore-not-found=true --timeout=30s || true
    kubectl delete service backend-service --ignore-not-found=true --timeout=30s || true
    kubectl delete service stack-service --ignore-not-found=true --timeout=30s || true
    kubectl delete service linkedlist-service --ignore-not-found=true --timeout=30s || true
    kubectl delete service graph-service --ignore-not-found=true --timeout=30s || true
    
    # Delete ConfigMaps and Secrets
    kubectl delete configmap frontend-config --ignore-not-found=true || true
    kubectl delete configmap backend-config --ignore-not-found=true || true
    kubectl delete configmap grafana-config --ignore-not-found=true || true
    kubectl delete configmap grafana-dashboards --ignore-not-found=true || true
    kubectl delete configmap prometheus-config --ignore-not-found=true || true
    
    kubectl delete secret backend-secrets --ignore-not-found=true || true
    kubectl delete secret database-credentials --ignore-not-found=true || true
    
    # Remove ingress controller (if deployed via manifests)
    echo "Removing ingress controller..."
    kubectl delete namespace ingress-nginx --ignore-not-found=true --timeout=60s || true
    
    # Wait for pods to terminate
    echo "Waiting for pods to terminate..."
    sleep 10
    
    # Force delete any remaining pods
    kubectl delete pods --all --force --grace-period=0 --ignore-not-found=true || true
    
    print_status "Kubernetes resources removed"
fi

# Clean Docker resources
if [ "$REMOVE_IMAGES" = "true" ] || [ "$CLEAN_ALL" = "true" ]; then
    print_header "Step 3: Cleaning Docker Resources"
    
    # Point Docker to Minikube daemon if using Minikube
    if command_exists minikube >/dev/null 2>&1; then
        eval $(minikube docker-env 2>/dev/null) || true
    fi
    
    # Remove application images
    echo "Removing application Docker images..."
    docker images --format "table {{.Repository}}:{{.Tag}}" | grep -E "(backend-service|ui-service|stack-service|linkedlist-service|graph-service)" | tail -n +2 | while read -r image; do
        if [ -n "$image" ]; then
            echo "Removing $image..."
            docker rmi "$image" 2>/dev/null || true
        fi
    done
    
    if [ "$CLEAN_ALL" = "true" ]; then
        echo "Removing all containers..."
        docker container prune -f
        
        echo "Removing all unused images..."
        docker image prune -a -f
        
        echo "Removing all unused volumes..."
        docker volume prune -f
        
        echo "Removing all unused networks..."
        docker network prune -f
    fi
    
    print_status "Docker cleanup completed"
fi

# Clean Minikube (if using and clean all is requested)
if [ "$CLEAN_ALL" = "true" ] && command_exists minikube >/dev/null 2>&1; then
    print_header "Step 4: Cleaning Minikube"
    
    if minikube status >/dev/null 2>&1; then
        echo "Stopping Minikube..."
        minikube stop
        print_status "Minikube stopped"
        
        echo "Deleting Minikube cluster..."
        minikube delete
        print_status "Minikube cluster deleted"
    fi
fi

# Clean log files and temporary data
print_header "Step 5: Cleaning Log Files and Temporary Data"

# Remove log files
if [ "$EC2_ENV" = true ]; then
    echo "Cleaning EC2 log files..."
    sudo rm -f /tmp/ingress-port-forward.log
    sudo rm -f /tmp/k8s-port-forward.pid
else
    echo "Cleaning local log files..."
    rm -f /tmp/ingress-port-forward.log
    rm -f /tmp/k8s-port-forward.pid
fi

# Remove temporary files
rm -f /tmp/minikube-logs-*
rm -f /tmp/kubectl-logs-*

# Clean generated files
if [ "$CLEAN_ALL" = "true" ]; then
    echo "Cleaning generated files..."
    rm -rf "$PROJECT_ROOT/.terraform"
    rm -f "$PROJECT_ROOT/terraform.tfstate"
    rm -f "$PROJECT_ROOT/terraform.tfstate.backup"
    rm -f "$PROJECT_ROOT/.terraform.lock.hcl"
    rm -rf "$PROJECT_ROOT/logs"
    rm -rf "$PROJECT_ROOT/tmp"
    
    print_status "Generated files cleaned"
fi

print_status "Log files and temporary data cleaned"

# Clean repository directories (if on EC2 and clean all is requested)
if [ "$EC2_ENV" = true ] && [ "$CLEAN_ALL" = "true" ]; then
    print_header "Step 6: Cleaning Repository Directories"
    
    # Remove cloned repositories
    if [ -d "/home/ubuntu/backend" ]; then
        echo "Removing backend repository..."
        sudo rm -rf /home/ubuntu/backend
    fi
    
    if [ -d "/home/ubuntu/frontend" ]; then
        echo "Removing frontend repository..."
        sudo rm -rf /home/ubuntu/frontend
    fi
    
    if [ -d "/home/ubuntu/aks_data_structures_devops" ]; then
        echo "Removing devops repository..."
        sudo rm -rf /home/ubuntu/aks_data_structures_devops
    fi
    
    print_status "Repository directories cleaned"
fi

# Final verification
print_header "Step 7: Verification"

echo "Checking for remaining resources..."

# Check Kubernetes resources
if kubectl cluster-info >/dev/null 2>&1; then
    REMAINING_PODS=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | wc -l)
    if [ "$REMAINING_PODS" -gt 0 ]; then
        print_warning "Found $REMAINING_PODS remaining pods"
        kubectl get pods --all-namespaces
    else
        print_status "No remaining pods found"
    fi
    
    REMAINING_SERVICES=$(kubectl get services --all-namespaces --no-headers 2>/dev/null | wc -l)
    if [ "$REMAINING_SERVICES" -gt 0 ]; then
        print_warning "Found $REMAINING_SERVICES remaining services"
        kubectl get services --all-namespaces
    else
        print_status "No remaining services found"
    fi
fi

# Check Docker resources
REMAINING_IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "(backend-service|ui-service|stack-service|linkedlist-service|graph-service)" | wc -l)
if [ "$REMAINING_IMAGES" -gt 0 ]; then
    print_warning "Found $REMAINING_IMAGES application images remaining"
else
    print_status "No application images remaining"
fi

# Summary
print_header "Cleanup Summary"

echo "✅ Port-forward services stopped"
echo "✅ Kubernetes resources removed"
if [ "$REMOVE_IMAGES" = "true" ]; then
    echo "✅ Docker images cleaned"
fi
if [ "$CLEAN_ALL" = "true" ]; then
    echo "✅ All resources cleaned (Minikube, generated files, repositories)"
fi
echo "✅ Log files and temporary data removed"

echo ""
echo -e "${GREEN}DevOps infrastructure cleanup completed!${NC}"

# Next steps
echo ""
echo -e "${BLUE}Next Steps:${NC}"
if [ "$CLEAN_ALL" = "true" ]; then
    echo "1. To redeploy: ./setup.sh"
    echo "2. To redeploy AWS infrastructure: cd ../aws-infrastrucutre-terraform && ./setup.sh"
else
    echo "1. To redeploy: ./setup.sh"
    echo "2. Check remaining resources with: kubectl get all"
fi

echo ""
echo -e "${BLUE}Manual Cleanup (if needed):${NC}"
echo "- Check remaining pods: kubectl get pods --all-namespaces"
echo "- Check remaining services: kubectl get services --all-namespaces"
echo "- Check Docker images: docker images | grep -E '(backend-service|ui-service|stack-service)'"
echo "- Remove specific image: docker rmi <image-name>"

echo ""
exit 0
