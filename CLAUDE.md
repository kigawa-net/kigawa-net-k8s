# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains Kubernetes manifests for kigawa.net infrastructure, managed via ArgoCD. The repository follows a GitOps pattern where all deployments are declarative and version-controlled.

## Architecture

### ArgoCD Application Structure

The repository uses a layered ArgoCD application pattern:

- **Root Application** (`apps/apps-app.yml`): Manages all child ArgoCD applications
- **Project Definition** (`apps/apps-app.yml`): Defines `kigawa-net` ArgoCD project with permissions
- **Child Applications**: Environment-specific deployments (dev, beta, production)

### Main Components

1. **Keruta** (`keruta/`): Session management and workspace system with Coder integration
   - `dev/`: Development environment (namespace: `kigawa-net-keruta-dev`)
   - `beta/`: Beta environment (namespace: `kigawa-net-keruta-beta`)
   - Components:
     - `ktse`: Backend server (Spring Boot, connects to TiDB and Zookeeper)
     - `ktcl-front`: Frontend (Node.js, JWT-based authentication)
     - ZooKeeper cluster for coordination

2. **Fonsole** (`fonsole/`): Backup management system
   - `fomage`: Web UI and API server (MongoDB backend)
   - Namespace: `fonsole`

3. **Diver-MC** (`diver-mc/`): Minecraft server deployment
   - StatefulSet with persistent storage
   - Spigot server on version 1.20.6

4. **TiDB** (`apps/keruta-dev-tidb-app.yml`): Distributed SQL database
   - Deployed via Helm chart in `tidb-system` namespace
   - Used by Keruta backend

## Common Operations

### Deploying Changes

Changes are automatically deployed via ArgoCD when merged to `main` branch:

```bash
# Verify manifests locally
kubectl apply --dry-run=client -f <manifest-file>

# Check ArgoCD sync status
argocd app list
argocd app get kigawa-net-keruta-dev-app
```

### Managing Secrets

Keruta requires several secrets in the target namespace:

```bash
# TiDB credentials (keruta-dev namespace)
kubectl create secret generic tidb \
  --from-literal=user="<username>" \
  --from-literal=pass="<password>" \
  --namespace=kigawa-net-keruta-dev

# Frontend JWT signing key
kubectl create secret generic ktcl-front \
  --from-literal=private-key="<private-key>" \
  --namespace=kigawa-net-keruta-dev

# MongoDB credentials (fonsole namespace)
kubectl create secret generic mongo \
  --from-literal=user="<username>" \
  --from-literal=pass="<password>" \
  --namespace=fonsole
```

### Working with Different Environments

Each service has environment-specific directories:
- Development deployments use `develop-latest` image tags with `imagePullPolicy: Always`
- Production/beta use pinned image tags with `imagePullPolicy: IfNotPresent`

### Updating Image Versions

```bash
# For development (uses develop-latest tag, no file change needed)
# Just rebuild and push the image, pod will pull on restart

# For production/beta, update the image tag in the manifest
# Example: fonsole/fomage.yaml
image: harbor.kigawa.net/library/fomage:main-<commit-sha>
```

## Key Dependencies

### Keruta Backend (ktse)
- **Database**: TiDB cluster via JDBC (`tidb-cluster-tidb.tidb-system.svc.cluster.local:4000`)
- **Coordination**: ZooKeeper (`zookeeper-svc:2181`)
- **Authentication**: JWT tokens validated against `https://user.kigawa.net/realms/develop`

### Keruta Frontend (ktcl-front)
- **Backend API**: Communicates with ktse backend
- **Identity Provider**: Keycloak at `user.kigawa.net`
- **Token Exchange**: Issues own JWTs for ktse audience

### Fomage
- **Database**: MongoDB (`mongo-svc.fonsole.svc.cluster.local:27017`)
- **Health Checks**: Exposes `/health` endpoint on port 8080

## Namespace Organization

- `argocd`: ArgoCD applications and projects
- `kigawa-net-keruta-dev`: Keruta development environment
- `kigawa-net-keruta-beta`: Keruta beta environment
- `tidb-system`: TiDB database cluster
- `fonsole`: Fonsole backup system
- Default namespace: Diver-MC Minecraft server

## Storage

- **StorageClass**: `rook-cephfs` for TiDB persistent volumes
- **PersistentVolumes**: Manually defined for specific services (e.g., diver-mc)

## Service Accounts and RBAC

Keruta dev environment uses a dedicated ServiceAccount (`keruta-dev-sa`) with RBAC permissions defined in `keruta/dev/rbac.yaml`.

## Image Registry

All images are hosted in Harbor registry:
- Registry: `harbor.kigawa.net`
- Library: `library`
- Format: `harbor.kigawa.net/library/<service>:<tag>`