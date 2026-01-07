# Architecture Overview

AKS Data Structures Platform — single-node Kubernetes (Minikube) running on AWS EC2, provisioned by Terraform, with local Docker builds pushed into Minikube. Ingress NGINX exposes path-based routing on port 80. Monitoring is Prometheus + Grafana. CI/CD reference is Jenkins.

## High-Level Diagram

```
AWS EC2 (single node)
└─ Minikube (control-plane + worker)
   ├─ Ingress NGINX (port 80)
   │   ├─ /        -> frontend-service (Nginx static UI)
   │   └─ /api     -> backend-service (Flask)
   ├─ backend-service (Python/Flask)
   │   └─ calls data-structure services
   ├─ ui-service (Nginx static content)
   ├─ stack-service (C)
   ├─ linkedlist-service (Java 17)
   ├─ graph-service (Python)
   └─ Monitoring
       ├─ Prometheus (scrapes pods, /metrics)
       └─ Grafana (dashboards)
```

## Components

### Ingress & Routing
- Ingress controller: NGINX (kubernetes/ingress-controller).
- Main ingress: `kubernetes/ingress/main-ingress.yaml`
  - `/` -> `frontend-service`
  - `/api` -> `backend-service`

### Frontend (ui-service)
- Static Nginx serving `index.html`, `app.js`, `styles.css`.
- Image: `ui-service:latest`.
- Manifests: `kubernetes/frontend/`.
- HPA: frontend-hpa (CPU-based).

### Backend (backend-service)
- Python Flask API.
- Image: `backend-service:latest`.
- Manifests: `kubernetes/backend/`.
- HPA: backend-hpa (CPU-based).
- Talks to data-structure services over ClusterIP.

### Data-Structure Services
- `stack-service` (C, port 5001)
- `linkedlist-service` (Java 17, port 5002)
- `graph-service` (Python, port 5003)
- Manifests: `kubernetes/data-structures/`.

### Monitoring
- Prometheus deployment: `kubernetes/monitoring/prometheus/`.
- Grafana deployment & dashboards: `kubernetes/monitoring/grafana/`.
- Grafana datasource: Prometheus at `http://prometheus-service:9090/prometheus`.

### CI/CD (reference)
- Jenkinsfile present for cloning/building/deploying; not required for manual runs.

## Infrastructure

- Terraform (aws-infrastrucutre-terraform) provisions:
  - VPC, subnets, SGs, and one EC2 host.
  - SSH key: `modules/ec2/keys/stack_key.pem`.
- Minikube runs inside the EC2 host using the Docker driver.
- Docker builds are executed against Minikube’s Docker daemon to avoid pull/push to a registry.

## Repository Structure

```
aks_data_structures_devops/
├─ ARCHITECTURE.md
├─ aws-infrastrucutre-terraform/        # Terraform: VPC + EC2
│  ├─ environments/dev/                 # tfvars/backend for dev
│  ├─ modules/                          # vpc, sg, ec2
│  ├─ setup.sh / destroy.sh             # infra provision/teardown
├─ devops-infra/                        # App platform (K8s/Minikube)
│  ├─ scripts/                          # main entrypoints
│  │  ├─ devops-setup.sh                # deploy platform on EC2/Minikube
│  │  └─ devops-destroy.sh              # tear down platform
│  ├─ kubernetes/                       # manifests
│  │  ├─ namespaces/
│  │  ├─ frontend/                      # UI
│  │  ├─ backend/                       # API + secrets/config
│  │  ├─ data-structures/               # stack/linkedlist/graph deployments
│  │  ├─ ingress/                       # routing rules
│  │  ├─ ingress-controller/            # NGINX controller
│  │  └─ monitoring/                    # Prometheus/Grafana
│  ├─ helm/                             # Helm charts (backend, etc.)
│  ├─ jenkins/                          # Jenkins pipeline files
│  ├─ README*.md                        # platform docs
│  └─ old_setup.sh                      # legacy setup script (reference)
├─ linkedlist/                          # Java linked-list service Docker ctx
├─ stack/                               # C stack service Docker ctx
├─ graph/                               # Python graph service Docker ctx
├─ Jenkinsfile-EC2                      # Jenkins pipeline example
└─ utils/ (if present)                  # supporting assets
```

## Deployment Flow (scripts)

1) **Infrastructure (Terraform)**
   - Path: `aws-infrastrucutre-terraform/setup.sh`
   - Creates VPC + EC2, outputs EC2 public IP.

2) **App Platform (Kubernetes on EC2 Minikube)**
   - Path: `devops-infra/scripts/devops-setup.sh`
   - Does:
     - Prereq checks
     - Ensures Minikube up and kubectl context set
     - Clones backend/frontend if missing (EC2 paths /home/ubuntu/backend, /home/ubuntu/frontend)
     - Builds Docker images inside Minikube’s Docker daemon
     - Forces `imagePullPolicy: IfNotPresent`
     - Applies namespaces, services, deployments, ingress, monitoring
     - Starts port-forward systemd service on port 80 (EC2)

3) **Cleanup**
   - Platform teardown: `devops-infra/scripts/devops-destroy.sh`
   - Infrastructure teardown: `aws-infrastrucutre-terraform/destroy.sh`

## Observability & Ports

- Ingress: port 80 on EC2 (systemd port-forward to ingress-nginx service).
- Prometheus: `kubectl port-forward svc/prometheus-service 9090:9090`
- Grafana: `kubectl port-forward svc/grafana-service 3000:3000`
- Logs: `kubectl logs -f deployment/<name>`

## Notable Behaviors

- `imagePullPolicy` is auto-fixed to `IfNotPresent` to use local images.
- ErrImageNeverPull pods are cleaned before redeploy.
- Port-forward runs as systemd on EC2 (k8s-port-forward.service).

## Runbook (quick)

1. Provision AWS infra:
   ```
   cd aws-infrastrucutre-terraform
   ./setup.sh
   ```
2. SSH to EC2 (stack_key.pem output by Terraform).
3. On EC2, deploy platform:
   ```
   cd ~/aks_data_structures_devops/devops-infra/scripts
   ./devops-setup.sh
   ```
4. Access:
   - Frontend: http://<EC2_PUBLIC_IP>/
   - API: http://<EC2_PUBLIC_IP>/api/
5. Teardown platform:
   ```
   cd ~/aks_data_structures_devops/devops-infra/scripts
   ./devops-destroy.sh
   ```
6. Teardown AWS infra (locally):
   ```
   cd aws-infrastrucutre-terraform
   ./destroy.sh
   ```

## Security & Credentials

- Repos are public; cloning uses HTTPS. If credentials are needed, update URLs accordingly.
- Secrets: backend secrets from `kubernetes/backend/secret.yaml` (base64-encoded).
- No external DB; services are stateless for this deployment.

## Scaling & Limits (current defaults)

- Frontend HPA: min 1, max 10 (CPU target in HPA manifest).
- Backend HPA: min 1, max 20 (CPU target in HPA manifest).
- Data-structure services: single replica each.

## Known Constraints

- Single-node Minikube; no multi-AZ or external DB.
- Uses local Docker daemon in Minikube; no remote registry.
- Systemd port-forward assumes Ubuntu + sudo.

