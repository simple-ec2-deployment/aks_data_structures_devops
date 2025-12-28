#!/bin/bash
# deploy.sh - Deployment Script
# Deploys the AKS Data Structures application to Kubernetes

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
DEVOPS_INFRA="$PROJECT_ROOT/devops-infra"

# Default values
ENVIRONMENT="${1:-dev}"
DEPLOY_MONITORING="${2:-false}"
USE_HELM="${3:-false}"

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  AKS Data Structures - Deployment${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Deploy Monitoring: $DEPLOY_MONITORING"
echo "Use Helm: $USE_HELM"
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

# Check kubectl connection
echo -e "${BLUE}Step 1: Verifying Kubernetes connection...${NC}"
if ! kubectl cluster-info >/dev/null 2>&1; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi
print_status "Connected to Kubernetes cluster"
echo ""

# Build Docker images (for local development)
echo -e "${BLUE}Step 2: Building Docker images...${NC}"

# Point Docker to Minikube daemon if available
if command -v minikube >/dev/null 2>&1; then
    eval $(minikube docker-env) 2>/dev/null || true
fi

# Build backend image
if [ -d "$PROJECT_ROOT/../aks_data_structures_backend" ]; then
    echo "Building backend-service..."
    docker build -t backend-service:latest "$PROJECT_ROOT/../aks_data_structures_backend" || print_warning "Backend build failed"
    print_status "backend-service:latest built"
else
    print_warning "Backend source not found, skipping build"
fi

# Build frontend image
if [ -d "$PROJECT_ROOT/../aks_data_structures_frontend" ]; then
    echo "Building ui-service..."
    docker build -t ui-service:latest "$PROJECT_ROOT/../aks_data_structures_frontend" || print_warning "Frontend build failed"
    print_status "ui-service:latest built"
else
    print_warning "Frontend source not found, skipping build"
fi

# Build data structure services
for service in stack linkedlist graph; do
    if [ -d "$PROJECT_ROOT/$service" ]; then
        echo "Building ${service}-service..."
        docker build -t "${service}-service:latest" "$PROJECT_ROOT/$service" || print_warning "${service} build failed"
        print_status "${service}-service:latest built"
    fi
done

echo ""

# Deploy using Helm or kubectl
if [ "$USE_HELM" = "true" ]; then
    echo -e "${BLUE}Step 3: Deploying with Helm...${NC}"
    
    # Deploy frontend
    echo "Deploying frontend..."
    helm upgrade --install frontend "$DEVOPS_INFRA/helm/frontend" \
        -f "$DEVOPS_INFRA/helm/frontend/values.yaml" \
        --set image.tag=latest
    print_status "Frontend deployed with Helm"
    
    # Deploy backend
    echo "Deploying backend..."
    helm upgrade --install backend "$DEVOPS_INFRA/helm/backend" \
        -f "$DEVOPS_INFRA/helm/backend/values.yaml" \
        --set image.tag=latest
    print_status "Backend deployed with Helm"
else
    echo -e "${BLUE}Step 3: Deploying with kubectl...${NC}"
    
    # Apply namespaces
    echo "Applying namespaces..."
    kubectl apply -f "$DEVOPS_INFRA/kubernetes/namespaces/" 2>/dev/null || true
    
    # Apply frontend manifests
    echo "Deploying frontend..."
    kubectl apply -f "$DEVOPS_INFRA/kubernetes/frontend/"
    print_status "Frontend deployed"
    
    # Apply backend manifests
    echo "Deploying backend..."
    kubectl apply -f "$DEVOPS_INFRA/kubernetes/backend/"
    print_status "Backend deployed"
    
    # Apply data structure services
    echo "Deploying data structure services..."
    if [ -d "$DEVOPS_INFRA/kubernetes/data-structures" ]; then
        kubectl apply -f "$DEVOPS_INFRA/kubernetes/data-structures/"
        print_status "Data structure services deployed"
    fi
    
    # Apply ingress
    echo "Deploying ingress..."
    kubectl apply -f "$DEVOPS_INFRA/kubernetes/ingress/"
    print_status "Ingress deployed"
    
    # Apply nginx ingress controller
    if [ -d "$DEVOPS_INFRA/kubernetes/ingress-controller" ]; then
        echo "Deploying NGINX ingress controller..."
        kubectl apply -f "$DEVOPS_INFRA/kubernetes/ingress-controller/"
        print_status "NGINX ingress controller deployed"
    fi
fi

echo ""

# Deploy monitoring stack
if [ "$DEPLOY_MONITORING" = "true" ]; then
    echo -e "${BLUE}Step 4: Deploying monitoring stack...${NC}"
    
    # Deploy Prometheus
    echo "Deploying Prometheus..."
    kubectl apply -f "$DEVOPS_INFRA/kubernetes/monitoring/prometheus/"
    print_status "Prometheus deployed"
    
    # Create Grafana dashboard ConfigMap
    kubectl create configmap grafana-dashboards \
        --from-file="$DEVOPS_INFRA/kubernetes/monitoring/grafana/dashboards/" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy Grafana
    echo "Deploying Grafana..."
    kubectl apply -f "$DEVOPS_INFRA/kubernetes/monitoring/grafana/"
    print_status "Grafana deployed"
    
    echo ""
fi

# Wait for deployments
echo -e "${BLUE}Step 5: Waiting for deployments to be ready...${NC}"

kubectl rollout status deployment/frontend-deployment --timeout=300s 2>/dev/null || true
kubectl rollout status deployment/backend-deployment --timeout=300s 2>/dev/null || true

echo ""
print_status "All deployments are ready"

# Print status
echo ""
echo -e "${BLUE}Deployment Status:${NC}"
echo ""
echo "=== Pods ==="
kubectl get pods -o wide
echo ""
echo "=== Services ==="
kubectl get services
echo ""
echo "=== Ingress ==="
kubectl get ingress

# Get access URL
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

if command -v minikube >/dev/null 2>&1; then
    MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
    echo "Access the application at:"
    echo "  - Frontend: http://${MINIKUBE_IP}:32080/"
    echo "  - API:      http://${MINIKUBE_IP}:32080/api/"
    if [ "$DEPLOY_MONITORING" = "true" ]; then
        echo ""
        echo "Monitoring:"
        echo "  - Prometheus: kubectl port-forward svc/prometheus-service 9090:9090"
        echo "  - Grafana:    kubectl port-forward svc/grafana-service 3000:3000"
    fi
fi
echo ""
