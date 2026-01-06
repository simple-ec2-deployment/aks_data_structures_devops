#!/bin/bash

# DevOps Infrastructure Setup Script
# Complete one-click deployment for AKS Data Structures Platform
# This script handles the full deployment after AWS infrastructure is ready

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
DEPLOY_MONITORING="${2:-true}"
USE_HELM="${3:-false}"
SKIP_BUILD="${4:-false}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  AKS Data Structures - DevOps Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Deploy Monitoring: $DEPLOY_MONITORING"
echo "Use Helm: $USE_HELM"
echo "Skip Docker Build: $SKIP_BUILD"
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
    echo -e "${BLUE}=== $1 ===${NC}"
    echo ""
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_header "Step 1: Checking Prerequisites"

# Check if we're on EC2 with pre-installed tools
if [ -f /etc/cloud/cloud-init.disabled ] || [ -d /home/ubuntu ]; then
    print_status "Detected EC2 environment"
    EC2_ENV=true
else
    EC2_ENV=false
fi

# Check Docker
if command_exists docker; then
    DOCKER_VERSION=$(docker --version)
    print_status "Docker installed: $DOCKER_VERSION"
    
    # Check if user can run docker without sudo
    if ! docker ps >/dev/null 2>&1; then
        print_warning "Docker requires sudo. Adding user to docker group..."
        if [ "$EC2_ENV" = true ]; then
            sudo usermod -aG docker ubuntu
            print_status "Added ubuntu user to docker group"
        else
            print_warning "Please add your user to docker group: sudo usermod -aG docker \$USER"
        fi
    fi
else
    print_error "Docker is not installed"
    if [ "$EC2_ENV" = true ]; then
        print_error "Docker should be pre-installed on EC2. Please check your EC2 setup."
    else
        print_error "Please install Docker: https://docs.docker.com/get-docker/"
    fi
    exit 1
fi

# Check kubectl
if command_exists kubectl; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null || kubectl version --client)
    print_status "kubectl installed: $KUBECTL_VERSION"
else
    print_error "kubectl is not installed"
    if [ "$EC2_ENV" = true ]; then
        print_error "kubectl should be pre-installed on EC2. Please check your EC2 setup."
    else
        print_error "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
    fi
    exit 1
fi

# Check Minikube
if command_exists minikube; then
    MINIKUBE_VERSION=$(minikube version --short 2>/dev/null || minikube version)
    print_status "Minikube installed: $MINIKUBE_VERSION"
else
    if [ "$EC2_ENV" = true ]; then
        print_error "Minikube should be pre-installed on EC2. Please check your EC2 setup."
    else
        print_warning "Minikube is not installed (required for local development)"
    fi
fi

# Check Terraform
if command_exists terraform; then
    TERRAFORM_VERSION=$(terraform version | head -n1)
    print_status "Terraform installed: $TERRAFORM_VERSION"
else
    print_error "Terraform is not installed"
    if [ "$EC2_ENV" = true ]; then
        print_error "Terraform should be pre-installed on EC2. Please check your EC2 setup."
    else
        print_error "Please install Terraform: https://www.terraform.io/downloads"
    fi
    exit 1
fi

# Check Helm
if command_exists helm; then
    HELM_VERSION=$(helm version --short)
    print_status "Helm installed: $HELM_VERSION"
else
    print_warning "Helm is not installed (optional)"
fi

# Check Git
if command_exists git; then
    GIT_VERSION=$(git --version)
    print_status "Git installed: $GIT_VERSION"
else
    print_error "Git is not installed"
    exit 1
fi

# Check AWS CLI
if command_exists aws; then
    AWS_VERSION=$(aws --version)
    print_status "AWS CLI installed: $AWS_VERSION"
else
    print_warning "AWS CLI is not installed (optional)"
fi

# Setup Kubernetes environment
print_header "Step 2: Setting up Kubernetes Environment"

if [ "$EC2_ENV" = true ]; then
    # On EC2, use Minikube
    print_status "Setting up Minikube on EC2..."
    
    # Ensure minikube/kube dirs exist and owned by ubuntu
    sudo mkdir -p /home/ubuntu/.minikube /home/ubuntu/.kube
    sudo chown -R ubuntu:ubuntu /home/ubuntu/.minikube /home/ubuntu/.kube
    
    # Fix Minikube directory permissions
    if [ ! -d "/home/ubuntu/.minikube" ]; then
        echo "Creating Minikube directory with proper permissions..."
        sudo mkdir -p /home/ubuntu/.minikube
        sudo chown -R ubuntu:ubuntu /home/ubuntu/.minikube
        print_status "Minikube directory created and permissions fixed"
    fi
    
    # Check if Minikube is running
    if sudo -u ubuntu minikube status >/dev/null 2>&1; then
        print_status "Minikube is already running"
    else
        print_status "Starting Minikube..."
        sudo -u ubuntu minikube start --driver=docker --memory=2500mb --cpus=2
        print_status "Minikube started successfully"
    fi
    
    # Set kubectl context
    sudo -u ubuntu kubectl config use-context minikube
    print_status "kubectl context set to minikube"
else
    # Local development
    if command_exists minikube; then
        if minikube status >/dev/null 2>&1; then
            print_status "Minikube is running"
        else
            print_status "Starting Minikube..."
            minikube start --driver=docker --memory=2500mb --cpus=2
            print_status "Minikube started"
        fi
        kubectl config use-context minikube
    else
        print_error "Please configure your Kubernetes context"
        exit 1
    fi
fi

# Verify kubectl connection
if kubectl cluster-info >/dev/null 2>&1; then
    print_status "Connected to Kubernetes cluster"
else
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# Clone repositories if needed
print_header "Step 3: Setting up Source Code"

# Repository URLs (same as Jenkins defaults)
INFRA_REPO_URL="github.com/simple-ec2-deployment/aks_data_structures_devops.git"
API_REPO_URL="github.com/simple-ec2-deployment/aks_data_structures_backend.git"
FRONTEND_REPO_URL="github.com/simple-ec2-deployment/aks_data_structures_frontend.git"

# Function to normalize URL
normalize_url() {
    local input="$1"
    if echo "$input" | grep -qiE '^git@github.com:'; then
        input=$(echo "$input" | sed -E 's|^git@github.com:|https://github.com/|')
    elif echo "$input" | grep -qiE '^ssh://git@github.com/'; then
        input=$(echo "$input" | sed -E 's|^ssh://git@github.com/|https://github.com/|')
    elif ! echo "$input" | grep -qiE '^https?://'; then
        input="https://$input"
    fi
    echo "$input"
}

# Function to clone repository
clone_repo() {
    local repo_url="$1"
    local target_dir="$2"
    local repo_name="$3"
    
    if [ ! -d "$target_dir" ]; then
        echo "Cloning $repo_name repository..."
        
        # Try cloning without authentication first (public repo)
        if ! git clone "$(normalize_url "$repo_url")" "$target_dir" 2>/dev/null; then
            echo "Public clone failed, trying with GitHub credentials..."
            # If that fails, we'll need credentials - for now, just show warning
            echo "⚠ Could not clone $repo_name. You may need to set up GitHub credentials or clone manually."
            return 1
        fi
        print_status "$repo_name repository cloned"
    else
        print_status "$repo_name repository already exists"
        # Update existing repository
        cd "$target_dir"
        git pull origin main 2>/dev/null || true
        cd - >/dev/null
    fi
}

if [ "$EC2_ENV" = true ]; then
    # On EC2, clone repositories to expected locations
    echo "Setting up repositories on EC2..."
    
    # Clone devops repository (should already be there)
    REPO_DIR="/home/ubuntu/aks_data_structures_devops"
    if [ ! -d "$REPO_DIR" ]; then
        clone_repo "$INFRA_REPO_URL" "$REPO_DIR" "devops"
    fi
    
    # Clone backend repository
    clone_repo "$API_REPO_URL" "/home/ubuntu/backend" "backend"
    
    # Clone frontend repository  
    clone_repo "$FRONTEND_REPO_URL" "/home/ubuntu/frontend" "frontend"
    
else
    # Local development - check if we have required repositories
    if [ ! -d "$PROJECT_ROOT/../aks_data_structures_backend" ]; then
        print_warning "Backend repository not found at ../aks_data_structures_backend"
    fi
    
    if [ ! -d "$PROJECT_ROOT/../aks_data_structures_frontend" ]; then
        print_warning "Frontend repository not found at ../aks_data_structures_frontend"
    fi
fi

# Build Docker images
if [ "$SKIP_BUILD" = "false" ]; then
    print_header "Step 4: Building Docker Images"
    
    # IMPORTANT: Use Minikube's Docker environment on EC2
    if [ "$EC2_ENV" = true ]; then
        # Point to Minikube's Docker daemon
        eval $(sudo -u ubuntu minikube docker-env) || true
        echo "✓ Using Minikube Docker environment"
    elif command_exists minikube >/dev/null 2>&1; then
        # Local development with Minikube
        eval $(minikube docker-env 2>/dev/null) || true
        echo "✓ Using Minikube Docker environment"
    fi
    
    # Docker command wrapper (preserve minikube env vars even when using sudo)
    DOCKER_CMD="docker"
    if [ "$EC2_ENV" = true ]; then
        DOCKER_CMD="sudo -E -u ubuntu env \
PATH=$PATH \
DOCKER_TLS_VERIFY=${DOCKER_TLS_VERIFY:-} \
DOCKER_HOST=${DOCKER_HOST:-} \
DOCKER_CERT_PATH=${DOCKER_CERT_PATH:-} \
DOCKER_API_VERSION=${DOCKER_API_VERSION:-} \
docker"
    fi
    
    # Check for ErrImageNeverPull pods and clean them up first
    if kubectl get pods | grep -q "ErrImageNeverPull"; then
        echo "⚠ Found pods with ErrImageNeverPull. Cleaning up..."
        kubectl delete deployment frontend-deployment backend-deployment stack-deployment linkedlist-deployment graph-deployment --ignore-not-found=true
        sleep 5
        print_status "Cleaned up problematic deployments"
    fi
    
    # Build backend image
    if [ "$EC2_ENV" = true ] && [ -d "/home/ubuntu/backend" ]; then
        echo "Building backend-service..."
        $DOCKER_CMD build -t backend-service:latest /home/ubuntu/backend || print_warning "Backend build failed"
        print_status "backend-service:latest built"
    elif [ -d "$PROJECT_ROOT/../aks_data_structures_backend" ]; then
        echo "Building backend-service..."
        $DOCKER_CMD build -t backend-service:latest "$PROJECT_ROOT/../aks_data_structures_backend" || print_warning "Backend build failed"
        print_status "backend-service:latest built"
    else
        print_warning "Backend source not found, skipping build"
    fi
    
    # Build frontend image
    if [ "$EC2_ENV" = true ] && [ -d "/home/ubuntu/frontend" ]; then
        echo "Building ui-service..."
        $DOCKER_CMD build -t ui-service:latest /home/ubuntu/frontend || print_warning "Frontend build failed"
        print_status "ui-service:latest built"
    elif [ -d "$PROJECT_ROOT/../aks_data_structures_frontend" ]; then
        echo "Building ui-service..."
        $DOCKER_CMD build -t ui-service:latest "$PROJECT_ROOT/../aks_data_structures_frontend" || print_warning "Frontend build failed"
        print_status "ui-service:latest built"
    else
        print_warning "Frontend source not found, skipping build"
    fi
    
    # Build data structure services
    for service in stack linkedlist graph; do
        if [ -d "$PROJECT_ROOT/$service" ]; then
            echo "Building ${service}-service..."
            $DOCKER_CMD build -t "${service}-service:latest" "$PROJECT_ROOT/$service" || print_warning "${service} build failed"
            print_status "${service}-service:latest built"
        else
            print_warning "$service source not found, skipping build"
        fi
    done
    
    # Verify images exist in Minikube Docker environment
    echo ""
    echo "Verifying images in Minikube Docker environment..."
    if [ "$EC2_ENV" = true ]; then
        IMAGES=$(sudo -u ubuntu docker images --format "table {{.Repository}}:{{.Tag}}" | grep -E "(backend-service|ui-service|stack-service|linkedlist-service|graph-service)")
    else
        IMAGES=$(docker images --format "table {{.Repository}}:{{.Tag}}" | grep -E "(backend-service|ui-service|stack-service|linkedlist-service|graph-service)")
    fi
    
    if [ -n "$IMAGES" ]; then
        echo "✓ Found required images:"
        echo "$IMAGES"
    else
        print_error "Required images not found in Minikube Docker environment"
        exit 1
    fi

    # List images for verification
    echo ""
    echo "Images built locally (current Docker context):"
    $DOCKER_CMD images --format "table {{.Repository}}:{{.Tag}}"
else
    print_status "Skipping Docker build as requested"
fi

# Deploy Kubernetes resources
print_header "Step 5: Deploying Kubernetes Resources"

DEVOPS_INFRA="$PROJECT_ROOT/devops-infra"

# Fix imagePullPolicy in deployment manifests (change Never to IfNotPresent for Minikube)
echo "Fixing imagePullPolicy for Minikube compatibility..."
find "$DEVOPS_INFRA/kubernetes" -name "*.yaml" -exec sed -i 's/imagePullPolicy: Never/imagePullPolicy: IfNotPresent/g' {} \;
print_status "Fixed imagePullPolicy in deployment manifests"

# Clean up existing deployments to ensure they use the updated manifests
echo "Cleaning up existing deployments..."
kubectl delete deployment frontend-deployment backend-deployment stack-deployment linkedlist-deployment graph-deployment --ignore-not-found=true
sleep 3
print_status "Cleaned up existing deployments"

# Apply namespaces
echo "Applying namespaces..."
kubectl apply -f "$DEVOPS_INFRA/kubernetes/namespaces/" 2>/dev/null || true
print_status "Namespaces applied"

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
else
    print_warning "Data structures manifests not found"
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

# Deploy monitoring stack if requested
if [ "$DEPLOY_MONITORING" = "true" ]; then
    print_header "Step 6: Deploying Monitoring Stack"
    
    # Deploy Prometheus
    echo "Deploying Prometheus..."
    kubectl apply -f "$DEVOPS_INFRA/kubernetes/monitoring/prometheus/"
    print_status "Prometheus deployed"
    
    # Create Grafana dashboard ConfigMap
    if [ -d "$DEVOPS_INFRA/kubernetes/monitoring/grafana/dashboards" ]; then
        kubectl create configmap grafana-dashboards \
            --from-file="$DEVOPS_INFRA/kubernetes/monitoring/grafana/dashboards/" \
            --dry-run=client -o yaml | kubectl apply -f -
    fi
    
    # Deploy Grafana
    echo "Deploying Grafana..."
    kubectl apply -f "$DEVOPS_INFRA/kubernetes/monitoring/grafana/"
    print_status "Grafana deployed"
fi

# Wait for deployments
print_header "Step 7: Waiting for Deployments"

echo "Waiting for frontend deployment..."
kubectl rollout status deployment/frontend-deployment --timeout=300s 2>/dev/null || print_warning "Frontend rollout timeout"

echo "Waiting for backend deployment..."
kubectl rollout status deployment/backend-deployment --timeout=300s 2>/dev/null || print_warning "Backend rollout timeout"

echo "Waiting for data structure services..."
kubectl rollout status deployment/stack-deployment --timeout=300s 2>/dev/null || print_warning "Stack rollout timeout"
kubectl rollout status deployment/linkedlist-deployment --timeout=300s 2>/dev/null || print_warning "LinkedList rollout timeout"
kubectl rollout status deployment/graph-deployment --timeout=300s 2>/dev/null || print_warning "Graph rollout timeout"

# Setup port forwarding for external access
print_header "Step 8: Setting up External Access"

# Kill existing port-forwards
pkill -f 'kubectl port-forward' || true
sleep 2

# Get kubectl path
KUBECTL_PATH=$(which kubectl)

# Create systemd service for persistent port-forward (only on EC2)
if [ "$EC2_ENV" = true ]; then
    echo "Setting up port-forward service on EC2..."
    
    sudo tee /etc/systemd/system/k8s-port-forward.service > /dev/null << EOF
[Unit]
Description=Kubernetes Port Forward for Ingress on Port 80
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/ubuntu
Environment="KUBECONFIG=/home/ubuntu/.kube/config"
ExecStart=${KUBECTL_PATH} port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 --address=0.0.0.0
Restart=always
RestartSec=5
StandardOutput=append:/tmp/ingress-port-forward.log
StandardError=append:/tmp/ingress-port-forward.log

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and start the service
    sudo systemctl daemon-reload
    sudo systemctl enable k8s-port-forward.service
    sudo systemctl restart k8s-port-forward.service
    
    # Wait for service to start
    sleep 3
    
    # Verify service is running
    if sudo systemctl is-active --quiet k8s-port-forward.service; then
        print_status "Port-forward service is running on port 80"
    else
        print_warning "Port-forward service failed to start"
    fi
else
    # Local development - start port-forward in background
    echo "Starting port-forward for local access..."
    kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 32080:80 --address=0.0.0.0 &
    PORT_FORWARD_PID=$!
    echo $PORT_FORWARD_PID > /tmp/k8s-port-forward.pid
    print_status "Port-forward started on port 32080 (PID: $PORT_FORWARD_PID)"
fi

# Display deployment status
print_header "Deployment Status"

echo "=== Pods ==="
kubectl get pods -o wide

echo ""
echo "=== Services ==="
kubectl get services

echo ""
echo "=== Ingress ==="
kubectl get ingress

echo ""
echo "=== Nodes ==="
kubectl get nodes

# Get access URLs
print_header "Access Information"

if [ "$EC2_ENV" = true ]; then
    # Get EC2 public IP
    EC2_PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "unknown")
    
    echo -e "${GREEN}Application is accessible at:${NC}"
    echo -e "  - Frontend: ${YELLOW}http://${EC2_PUBLIC_IP}/${NC}"
    echo -e "  - API:      ${YELLOW}http://${EC2_PUBLIC_IP}/api/${NC}"
    
    if [ "$DEPLOY_MONITORING" = "true" ]; then
        echo ""
        echo -e "${BLUE}Monitoring (port-forward required):${NC}"
        echo "  - Prometheus: kubectl port-forward svc/prometheus-service 9090:9090"
        echo "  - Grafana:    kubectl port-forward svc/grafana-service 3000:3000"
    fi
    
    echo ""
    echo -e "${BLUE}Service Management:${NC}"
    echo "  - View port-forward logs: tail -f /tmp/ingress-port-forward.log"
    echo "  - Restart port-forward: sudo systemctl restart k8s-port-forward"
    echo "  - Stop port-forward: sudo systemctl stop k8s-port-forward"
else
    # Local development
    MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
    
    echo -e "${GREEN}Application is accessible at:${NC}"
    echo -e "  - Frontend: ${YELLOW}http://${MINIKUBE_IP}:32080/${NC}"
    echo -e "  - API:      ${YELLOW}http://${MINIKUBE_IP}:32080/api/${NC}"
    
    if [ "$DEPLOY_MONITORING" = "true" ]; then
        echo ""
        echo -e "${BLUE}Monitoring:${NC}"
        echo "  - Prometheus: kubectl port-forward svc/prometheus-service 9090:9090"
        echo "  - Grafana:    kubectl port-forward svc/grafana-service 3000:3000"
    fi
fi

# Final summary
print_header "Setup Complete!"

echo "✅ Prerequisites checked"
echo "✅ Kubernetes environment configured"
echo "✅ Source code repositories prepared"
echo "✅ Docker images built"
echo "✅ Kubernetes resources deployed"
echo "✅ External access configured"
echo "✅ Monitoring stack deployed" $([ "$DEPLOY_MONITORING" = "true" ] && echo "" || echo "(skipped)")

echo ""
echo -e "${GREEN}Your AKS Data Structures Platform is ready!${NC}"
echo ""

# Next steps
echo -e "${BLUE}Next Steps:${NC}"
if [ "$EC2_ENV" = true ]; then
    echo "1. Ensure AWS Security Group allows port 80"
    echo "2. Access the application using the URLs above"
    echo "3. Check pod status: kubectl get pods"
    echo "4. View logs: kubectl logs -f deployment/frontend-deployment"
else
    echo "1. Access the application using the URLs above"
    echo "2. Check pod status: kubectl get pods"
    echo "3. View logs: kubectl logs -f deployment/frontend-deployment"
    echo "4. Stop port-forward: kill \$(cat /tmp/k8s-port-forward.pid)"
fi

echo ""
echo -e "${BLUE}Troubleshooting:${NC}"
echo "- Check pod status: kubectl get pods -o wide"
echo "- View pod logs: kubectl logs <pod-name>"
echo "- Describe pod: kubectl describe pod <pod-name>"
echo "- Check ingress: kubectl describe ingress ingress-nginx"
echo ""

exit 0
