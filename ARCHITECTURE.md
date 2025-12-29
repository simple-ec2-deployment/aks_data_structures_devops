# Architecture Documentation

Complete architecture documentation for the AKS Data Structures Platform.

## System Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                            AWS Cloud                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│   ┌──────────────────────────────────────────────────────────────┐   │
│   │                    Kubernetes Cluster                        │   │
│   │                                                               │   │
│   │   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │   │
│   │   │   Frontend   │    │   Backend    │    │   Database   │  │   │
│   │   │   (React)    │───▶│   (Flask)    │───▶│ (PostgreSQL) │  │   │
│   │   │              │    │              │    │              │  │   │
│   │   │  Replicas: 2 │    │  Replicas: 2 │    │ Replicas: 1  │  │   │
│   │   │  HPA: 2-10   │    │  HPA: 2-20   │    │ StatefulSet  │  │   │
│   │   └──────────────┘    └──────────────┘    └──────────────┘  │   │
│   │                                                               │   │
│   │   ┌──────────────────────────────────────────────────────┐  │   │
│   │   │              Data Structure Services                  │  │   │
│   │   │  ┌──────┐  ┌──────────┐  ┌──────┐                    │  │   │
│   │   │  │Stack │  │LinkedList│  │Graph │                    │  │   │
│   │   │  │ (C)  │  │  (Java)  │  │(Py)  │                    │  │   │
│   │   │  └──────┘  └──────────┘  └──────┘                    │  │   │
│   │   └──────────────────────────────────────────────────────┘  │   │
│   │                                                               │   │
│   │   ┌──────────────────────────────────────────────────────┐  │   │
│   │   │              Monitoring Stack                        │  │   │
│   │   │  ┌──────────┐         ┌──────────┐                    │  │   │
│   │   │  │Prometheus│────────▶│ Grafana │                    │  │   │
│   │   │  │          │         │          │                    │  │   │
│   │   │  │ Metrics  │         │Dashboards│                    │  │   │
│   │   │  │  Alerts  │         │  Alerts  │                    │  │   │
│   │   │  └──────────┘         └──────────┘                    │  │   │
│   │   └──────────────────────────────────────────────────────┘  │   │
│   │                                                               │   │
│   │   ┌──────────────┐                                           │   │
│   │   │   Ingress    │◀── External Traffic                      │   │
│   │   │  Controller  │                                           │   │
│   │   └──────────────┘                                           │   │
│   │                                                               │   │
│   └──────────────────────────────────────────────────────────────┘   │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
                              ▲
                              │
                    ┌─────────┴─────────┐
                    │   CI/CD Pipeline   │
                    │     (Jenkins)      │
                    │                    │
                    │  ┌──────────────┐  │
                    │  │  Build       │  │
                    │  │  Test        │  │
                    │  │  Scan        │  │
                    │  │  Deploy      │  │
                    │  └──────────────┘  │
                    └─────────┬─────────┘
                              │
                    ┌─────────┴─────────┐
                    │  GitHub Repos     │
                    │  Frontend/Backend │
                    └───────────────────┘
```

## Component Details

### 1. Frontend Service

**Technology Stack:**
- Framework: React/Vue.js
- Web Server: Nginx
- Container: Multi-stage Docker build

**Deployment:**
- Type: Kubernetes Deployment
- Replicas: 2 (minimum)
- Auto-scaling: 2-10 pods (CPU 70%)
- Resources:
  - Requests: 100m CPU, 128Mi Memory
  - Limits: 500m CPU, 256Mi Memory

**Health Checks:**
- Liveness: `/health`
- Readiness: `/health`

**Configuration:**
- API URL via ConfigMap
- Environment via Helm values

### 2. Backend Service

**Technology Stack:**
- Framework: Flask
- WSGI Server: Gunicorn
- Database: PostgreSQL (SQLAlchemy)
- Metrics: Prometheus client

**Deployment:**
- Type: Kubernetes Deployment
- Replicas: 2 (minimum)
- Auto-scaling: 2-20 pods (CPU 70%)
- Resources:
  - Requests: 200m CPU, 256Mi Memory
  - Limits: 1000m CPU, 512Mi Memory

**Endpoints:**
- `/health` - Basic health check
- `/health/ready` - Readiness (DB connected)
- `/health/live` - Liveness probe
- `/metrics` - Prometheus metrics
- `/api/*` - REST API endpoints

**Metrics Exposed:**
- `http_requests_total` (counter)
- `http_request_duration_seconds` (histogram)
- `http_requests_in_progress` (gauge)
- `db_connections_active` (gauge)

**Configuration:**
- Database URL from Secret
- Service URLs from ConfigMap
- Environment variables from Helm

### 3. Database Service

**Technology Stack:**
- Database: PostgreSQL 15
- Storage: Persistent Volume Claim

**Deployment:**
- Type: StatefulSet
- Replicas: 1
- Storage: 10Gi PVC
- Resources:
  - Requests: 250m CPU, 256Mi Memory
  - Limits: 1000m CPU, 512Mi Memory

**Configuration:**
- Credentials from Kubernetes Secrets
- Database name: `appdb`
- User: `appuser`

### 4. Data Structure Services

**Stack Service (C):**
- Port: 5001
- Language: C
- Endpoint: `/stack`

**LinkedList Service (Java):**
- Port: 5002
- Language: Java
- Endpoint: `/linkedlist`

**Graph Service (Python):**
- Port: 5003
- Language: Python
- Endpoint: `/graph`

### 5. Monitoring Stack

#### Prometheus

**Configuration:**
- Scrape interval: 15s
- Retention: 15 days
- Targets:
  - Kubernetes pods (auto-discovery)
  - Backend service
  - Frontend service
  - Data structure services

**Alert Rules:**
- High error rate (>5%)
- High latency (p95 >1s)
- Pod restarts
- Database connection failures
- High CPU/Memory usage

#### Grafana

**Dashboards:**
1. **Application Dashboard**
   - Request rate
   - Error rate
   - Response time (p50, p95, p99)
   - Active connections

2. **Kubernetes Dashboard**
   - Pod status
   - Resource usage
   - Node health
   - Deployment status

**Data Source:**
- Prometheus (default)

### 6. CI/CD Pipeline

**Jenkins Pipeline Stages:**

1. **Checkout**
   - Clone DevOps repo
   - Clone Frontend repo
   - Clone Backend repo

2. **Build**
   - Build Docker images
   - Multi-stage builds
   - Optimized layer caching

3. **Test**
   - Unit tests
   - Integration tests
   - Linting

4. **Scan**
   - Security scanning (Trivy)
   - Code quality checks

5. **Tag**
   - Build number tag
   - Git SHA tag
   - Latest tag

6. **Push**
   - Push to container registry
   - Production only

7. **Deploy**
   - Deploy via Helm
   - Environment-specific values
   - Rolling updates

8. **Verify**
   - Health checks
   - Integration tests
   - Smoke tests

**Pipeline Files:**
- `Jenkinsfile` - Main orchestration
- `Jenkinsfile.frontend` - Frontend pipeline
- `Jenkinsfile.backend` - Backend pipeline

### 7. Infrastructure as Code

#### Terraform Modules

**Networking Module:**
- VPC with CIDR
- Public subnets
- Private subnets
- Internet Gateway
- NAT Gateway (optional)
- Route tables

**Kubernetes Module:**
- Namespace creation
- Deployment application
- Service creation
- HPA configuration
- Ingress setup

**Database Module:**
- RDS PostgreSQL instance
- Security groups
- Subnet groups
- Secrets Manager integration
- Backup configuration

#### Helm Charts

**Backend Chart:**
- Environment awareness
- Feature toggles
- Configurable scaling
- Resource management

**Frontend Chart:**
- Environment awareness
- Feature toggles
- Configurable scaling
- Resource management

## Data Flow

### Request Flow

```
User Request
    ↓
Load Balancer / Ingress
    ↓
Frontend Service (2+ pods)
    ↓
Backend Service (2+ pods)
    ↓
Database (PostgreSQL)
    ↓
Response
```

### Metrics Flow

```
Application Pods
    ↓
Prometheus Scraping (15s interval)
    ↓
Prometheus Storage (15 days retention)
    ↓
Grafana Visualization
    ↓
Dashboards & Alerts
```

### CI/CD Flow

```
GitHub Push
    ↓
Webhook Trigger
    ↓
Jenkins Pipeline
    ↓
Build & Test
    ↓
Docker Image
    ↓
Container Registry
    ↓
Kubernetes Deployment (Helm)
    ↓
Running Application
```

## Security

### Secrets Management

- **Kubernetes Secrets**: Database credentials, API keys
- **AWS Secrets Manager**: RDS passwords (for cloud)
- **Base64 encoding**: For Kubernetes secrets

### Network Security

- **Security Groups**: Restrict database access
- **Network Policies**: (Optional) Pod-to-pod communication
- **TLS/SSL**: (Optional) Ingress with cert-manager

### Container Security

- **Non-root users**: All containers run as non-root
- **Image scanning**: Trivy security scans
- **Resource limits**: Prevent resource exhaustion

## Scalability

### Horizontal Pod Autoscaling (HPA)

**Frontend:**
- Min replicas: 2
- Max replicas: 10
- Target CPU: 70%

**Backend:**
- Min replicas: 2
- Max replicas: 20
- Target CPU: 70%

### Database Scaling

- **Vertical scaling**: Increase instance class
- **Read replicas**: (Optional) For read-heavy workloads
- **Connection pooling**: Managed by application

## High Availability

### Application Level

- **Multiple replicas**: Minimum 2 pods per service
- **Rolling updates**: Zero-downtime deployments
- **Health checks**: Automatic pod replacement

### Infrastructure Level

- **Multi-AZ deployment**: (AWS) Across availability zones
- **Persistent storage**: Database with backups
- **Load balancing**: Ingress controller

## Monitoring & Observability

### Metrics

- **Application metrics**: Request rate, latency, errors
- **Infrastructure metrics**: CPU, memory, disk
- **Database metrics**: Connections, queries, performance

### Logging

- **Container logs**: `kubectl logs`
- **Centralized logging**: (Optional) EFK/Loki stack

### Tracing

- **Distributed tracing**: (Optional) Jaeger integration

## Disaster Recovery

### Backups

- **Database backups**: Automated daily backups
- **Retention**: 7 days (configurable)
- **Snapshot**: Before major changes

### Recovery Procedures

1. **Database restore**: From automated backups
2. **Application rollback**: Helm rollback command
3. **Infrastructure restore**: Terraform state management

## Cost Optimization

### Resource Management

- **Right-sizing**: Appropriate resource requests/limits
- **Auto-scaling**: Scale down during low traffic
- **Spot instances**: (Optional) For non-critical workloads

### Storage

- **PVC sizing**: Appropriate storage allocation
- **Cleanup policies**: Remove unused resources

## Best Practices

### Development

- **Git branching**: Feature branches, main/master for production
- **Code reviews**: Required before merge
- **Testing**: Unit and integration tests

### Deployment

- **Blue-green**: (Optional) Zero-downtime deployments
- **Canary**: (Optional) Gradual rollout
- **Rollback**: Quick rollback capability

### Operations

- **Monitoring**: 24/7 monitoring with alerts
- **Documentation**: Keep documentation updated
- **Incident response**: Defined procedures

---

For deployment instructions, see [DEPLOYMENT.md](devops-infra/DEPLOYMENT.md).

