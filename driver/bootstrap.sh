#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { printf "${GREEN}[BOOTSTRAP]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

ensure_pkg() {
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    return
  fi
  sudo apt-get install -y "$pkg"
}

log "Updating apt cache..."
sudo apt-get update -y

log "Installing base packages..."
BASE_PKGS=(
  ca-certificates curl gnupg lsb-release apt-transport-https
  software-properties-common unzip git python3 python3-pip
  docker.io conntrack socat
)
for pkg in "${BASE_PKGS[@]}"; do
  ensure_pkg "$pkg"
done

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

log "Ensuring Docker is running and user is in docker group..."
sudo systemctl enable docker >/dev/null 2>&1 || true
sudo systemctl start docker  >/dev/null 2>&1 || true
if groups "$USER" | grep -q '\bdocker\b'; then
  :
else
  sudo usermod -aG docker "$USER"
  warn "You were added to the docker group. Log out/in (or reboot) for it to take effect."
fi

log "Installing pip requirements (if any)..."
REQ_FILE="$(dirname "$0")/requirements.txt"
if [ -s "$REQ_FILE" ]; then
  python3 -m pip install --user -r "$REQ_FILE"
else
  warn "requirements.txt is empty; skipping."
fi

log "Versions:"
kubectl version --client --short || true
minikube version || true
terraform version | head -n1 || true
docker --version || true
git --version || true
python3 --version || true

log "Bootstrap complete."
