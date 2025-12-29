#!/bin/bash

# One-Click Deployment Script for EC2/Minikube (4GB RAM, 2 CPU)
# This script deploys the complete architecture on a single EC2 instance with Minikube

set -e

echo "==========================================="
echo "AKS Data Structures Platform - EC2/Minikube Deployment"
echo "==========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${1:-prod}
DEPLOY_MONITORING=${2:-true}
K8S_DIR="devops-infra/kubernetes"

# Check prerequisites
echo -e "${GREEN}Checking prerequisites...${NC}"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker is installed${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl is installed${NC}"

# Check if Minikube is available
if ! command -v minikube &> /dev/null; then
    echo -e "${RED}Error: Minikube is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Minikube is installed${NC}"

# Check Minikube status and start if needed
echo -e "${YELLOW}Checking Minikube status...${NC}"
if ! minikube status &> /dev/null; then
    echo -e "${YELLOW}Minikube is not running. Starting Minikube...${NC}"
    minikube start || {
        echo -e "${RED}Error: Failed to start Minikube${NC}"
        exit 1
    }
else
    echo -e "${GREEN}✓ Minikube is running${NC}"
fi

# Configure kubectl for Minikube
echo -e "${YELLOW}Configuring kubectl for Minikube...${NC}"
minikube update-context || true

# Set Docker to use Minikube's Docker daemon
echo -e "${YELLOW}Configuring Docker to use Minikube daemon...${NC}"
eval $(minikube docker-env) || {
    echo -e "${YELLOW}⚠ Could not configure Minikube Docker env, continuing...${NC}"
}

# Verify kubectl access
if kubectl get nodes &> /dev/null; then
    echo -e "${GREEN}✓ kubectl is configured and can access cluster${NC}"
else
    echo -e "${YELLOW}⚠ kubectl may need configuration, but continuing...${NC}"
fi

echo ""

echo -e "${GREEN}Step 1: Creating namespace${NC}"
kubectl apply -f ${K8S_DIR}/namespaces/namespace.yaml || kubectl create namespace default --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}Step 2: Deploying database${NC}"
kubectl apply -f ${K8S_DIR}/database/secret.yaml
kubectl apply -f ${K8S_DIR}/database/pvc.yaml
kubectl apply -f ${K8S_DIR}/database/service.yaml
kubectl apply -f ${K8S_DIR}/database/statefulset.yaml

echo "Waiting for database to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres --timeout=300s || echo "Database may still be starting..."

echo -e "${GREEN}Step 3: Deploying backend${NC}"
kubectl apply -f ${K8S_DIR}/backend/secret.yaml
kubectl apply -f ${K8S_DIR}/backend/configmap.yaml
kubectl apply -f ${K8S_DIR}/backend/deployment.yaml
kubectl apply -f ${K8S_DIR}/backend/service.yaml
kubectl apply -f ${K8S_DIR}/backend/hpa.yaml

echo -e "${GREEN}Step 4: Deploying frontend${NC}"
kubectl apply -f ${K8S_DIR}/frontend/configmap.yaml
kubectl apply -f ${K8S_DIR}/frontend/deployment.yaml
kubectl apply -f ${K8S_DIR}/frontend/service.yaml
kubectl apply -f ${K8S_DIR}/frontend/hpa.yaml

echo -e "${GREEN}Step 5: Deploying data structure services${NC}"
kubectl apply -f ${K8S_DIR}/data-structures/stack.yaml
kubectl apply -f ${K8S_DIR}/data-structures/linkedlist.yaml
kubectl apply -f ${K8S_DIR}/data-structures/graph.yaml

echo -e "${GREEN}Step 6: Deploying ingress controller${NC}"
kubectl apply -f ${K8S_DIR}/ingress-controller/nginx-ingress-controller.yaml

echo -e "${GREEN}Step 7: Deploying ingress${NC}"
kubectl apply -f ${K8S_DIR}/ingress/ingress.yaml

if [ "$DEPLOY_MONITORING" = "true" ]; then
    echo -e "${GREEN}Step 8: Deploying monitoring stack${NC}"
    
    # Deploy Prometheus
    kubectl apply -f ${K8S_DIR}/monitoring/prometheus/clusterrole.yaml
    kubectl apply -f ${K8S_DIR}/monitoring/prometheus/configmap.yaml
    kubectl apply -f ${K8S_DIR}/monitoring/prometheus/alerts.yaml
    kubectl apply -f ${K8S_DIR}/monitoring/prometheus/deployment.yaml
    kubectl apply -f ${K8S_DIR}/monitoring/prometheus/service.yaml
    
    # Deploy Grafana
    kubectl apply -f ${K8S_DIR}/monitoring/grafana/configmap.yaml
    kubectl apply -f ${K8S_DIR}/monitoring/grafana/deployment.yaml
    kubectl apply -f ${K8S_DIR}/monitoring/grafana/service.yaml
fi

echo ""
echo -e "${GREEN}Step 9: Waiting for all pods to be ready...${NC}"
sleep 10

# Wait for pods with timeout
echo "Waiting for frontend..."
kubectl wait --for=condition=ready pod -l app=frontend --timeout=180s || echo "Frontend may still be starting..."

echo "Waiting for backend..."
kubectl wait --for=condition=ready pod -l app=backend --timeout=180s || echo "Backend may still be starting..."

echo ""
echo -e "${GREEN}==========================================="
echo "Deployment Summary"
echo "===========================================${NC}"
echo ""
echo "Pod Status:"
kubectl get pods -o wide
echo ""
echo "Services:"
kubectl get services
echo ""
echo "Ingress:"
kubectl get ingress
echo ""

# Get service URLs
echo -e "${YELLOW}Access URLs:${NC}"
echo ""

# Try to get NodePort or LoadBalancer IP
INGRESS_IP=$(kubectl get ingress main-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
INGRESS_HOST=$(kubectl get ingress main-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$INGRESS_IP" ]; then
    echo "Frontend: http://${INGRESS_IP}/"
    echo "Backend API: http://${INGRESS_IP}/api/"
    echo "Prometheus: http://${INGRESS_IP}/prometheus/"
    echo "Grafana: http://${INGRESS_IP}/grafana/"
elif [ -n "$INGRESS_HOST" ]; then
    echo "Frontend: http://${INGRESS_HOST}/"
    echo "Backend API: http://${INGRESS_HOST}/api/"
    echo "Prometheus: http://${INGRESS_HOST}/prometheus/"
    echo "Grafana: http://${INGRESS_HOST}/grafana/"
else
    # Get NodePort if available
    NODE_PORT=$(kubectl get svc ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "")
    if [ -n "$NODE_PORT" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
        echo "Frontend: http://${NODE_IP}:${NODE_PORT}/"
        echo "Backend API: http://${NODE_IP}:${NODE_PORT}/api/"
        echo "Prometheus: http://${NODE_IP}:${NODE_PORT}/prometheus/"
        echo "Grafana: http://${NODE_IP}:${NODE_PORT}/grafana/"
    else
        echo "Run 'kubectl get ingress' to get the access URL"
    fi
fi

echo ""
echo -e "${GREEN}==========================================="
echo "Deployment completed successfully!"
echo "===========================================${NC}"
echo ""
echo "To check pod status: kubectl get pods"
echo "To view logs: kubectl logs <pod-name>"
echo "To access services: kubectl port-forward svc/<service-name> <port>"
echo ""

