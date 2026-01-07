#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { printf "${GREEN}[BOOTSTRAP]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# Use SSH user even when script is run with sudo
TARGET_USER="${SUDO_USER:-${USER:-ubuntu}}"
TARGET_HOME="/home/${TARGET_USER}"

log "Updating apt cache..."
sudo apt-get update -y

log "Installing base packages..."
sudo apt-get install -y \
  ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common \
  unzip git python3 python3-pip docker.io conntrack socat net-tools openjdk-17-jdk

if ! need_cmd aws; then
  log "Installing AWS CLI v2 (official installer)..."
  ARCH="$(uname -m)"
  if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    AWS_ARCH="aarch64"
  else
    AWS_ARCH="x86_64"
  fi
  curl -L "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install
  rm -rf /tmp/aws /tmp/awscliv2.zip
else
  warn "AWS CLI already installed; skipping."
fi

if ! need_cmd kubectl; then
  log "Installing kubectl..."
  K_VER="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
  curl -L "https://dl.k8s.io/release/${K_VER}/bin/linux/amd64/kubectl" -o /tmp/kubectl
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
else
  warn "kubectl already installed; skipping."
fi

if ! need_cmd minikube; then
  log "Installing Minikube..."
  curl -L "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64" -o /tmp/minikube
  sudo install -m 0755 /tmp/minikube /usr/local/bin/minikube
else
  warn "Minikube already installed; skipping."
fi

if ! need_cmd terraform; then
  log "Installing Terraform..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y terraform
else
  warn "Terraform already installed; skipping."
fi

log "Installing Jenkins..."
if ! need_cmd jenkins; then
  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y jenkins
  sudo systemctl enable jenkins >/dev/null 2>&1 || true
  sudo systemctl start jenkins  >/dev/null 2>&1 || true
else
  warn "Jenkins already installed; skipping."
fi

log "Configuring Java 17 for Jenkins..."
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java || true
if grep -q "^JAVA_HOME=" /etc/default/jenkins; then
  sudo sed -i 's|^JAVA_HOME=.*|JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64|' /etc/default/jenkins
else
  echo 'JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' | sudo tee -a /etc/default/jenkins >/dev/null
fi
sudo systemctl daemon-reload || true
sudo systemctl enable jenkins >/dev/null 2>&1 || true
sudo systemctl restart jenkins  >/dev/null 2>&1 || true

# Wait briefly for Jenkins to start and then print admin password and URL
log "Checking Jenkins status and admin password..."
for i in $(seq 1 12); do
  if sudo systemctl is-active --quiet jenkins; then
    if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
      ADMIN_PASS=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || true)
      if [ -n "$ADMIN_PASS" ]; then
        log "Jenkins admin password: $ADMIN_PASS"
      fi
    fi
    PUB_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || true)
    if [ -z "$PUB_IP" ]; then
      PUB_IP=$(curl -s https://checkip.amazonaws.com || true)
    fi
    if [ -z "$PUB_IP" ]; then
      PUB_IP=$(dig +short myip.opendns.com @resolver1.opendns.com || true)
    fi
    if [ -z "$PUB_IP" ]; then
      PUB_IP=$(hostname -I | awk '{print $1}')
    fi
    if [ -n "$PUB_IP" ]; then
      log "Jenkins URL: http://${PUB_IP}:8080/"
    else
      warn "Could not determine public IP for Jenkins URL."
    fi
    break
  fi
  sleep 5
done

log "Ensuring Docker is running..."
sudo systemctl enable docker >/dev/null 2>&1 || true
sudo systemctl start docker  >/dev/null 2>&1 || true

if groups "$USER" | grep -q '\bdocker\b'; then
  :
else
  sudo usermod -aG docker "$USER"
  warn "User added to docker group; re-login may be required."
fi

# Ensure kubectl/minikube directories exist and owned by ssh user
sudo mkdir -p /home/${USER}/.kube /home/${USER}/.minikube
sudo chown -R ${USER}:${USER} /home/${USER}/.kube /home/${USER}/.minikube

# Clone infrastructure repo (idempotent)
REPO_URL="${REPO_URL:-https://github.com/simple-ec2-deployment/aks_data_structures_devops.git}"
REPO_DIR="/home/${USER}/aks_data_structures_devops"
if [ ! -d "$REPO_DIR/.git" ]; then
  log "Cloning infrastructure repo to $REPO_DIR"
  git clone "$REPO_URL" "$REPO_DIR" || warn "Clone failed; please check credentials or network"
else
  log "Repo already present at $REPO_DIR"
  (cd "$REPO_DIR" && git pull --ff-only || warn "Git pull failed; please check repo access")
fi
sudo chown -R ${USER}:${USER} "$REPO_DIR"

log "Versions:"
if need_cmd kubectl; then kubectl version --client || true; else warn "kubectl not found"; fi
if need_cmd minikube; then minikube version || true; else warn "minikube not found"; fi
if need_cmd terraform; then terraform version | head -n1 || true; else warn "terraform not found"; fi
if need_cmd docker; then docker --version || true; else warn "docker not found"; fi
if need_cmd git; then git --version || true; else warn "git not found"; fi
if need_cmd python3; then python3 --version || true; else warn "python3 not found"; fi
if need_cmd aws; then aws --version || true; else warn "aws not found"; fi

if need_cmd jenkins; then
  log "Jenkins detected; showing admin info..."
  if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    ADMIN_PASS=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || true)
    if [ -n "$ADMIN_PASS" ]; then
      log "Jenkins admin password: $ADMIN_PASS"
    else
      warn "Jenkins admin password file empty or unreadable."
    fi
  else
    warn "Jenkins admin password file not found yet."
  fi
  PUB_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || hostname -I | awk '{print $1}')
  if [ -n "$PUB_IP" ]; then
    log "Jenkins URL: http://${PUB_IP}:8080/"
  fi
fi

log "Bootstrap complete."
