# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
日本語で話す

## Repository Overview

Kubernetes manifests for kigawa.net infrastructure, managed via ArgoCD GitOps. Merging to `main` automatically triggers deployment.

## ArgoCD Application Structure

Layered pattern: a root app (`apps/apps-app.yml`) recursively syncs everything in `apps/`, which contains child `Application` resources pointing at subdirectories.

- **Root**: `apps/apps-app.yml` — manages all children + defines the `kigawa-net` AppProject
- **Sync policy**: All apps use automated sync with prune enabled; selfHeal is enabled only for MAAS and TiDB
- **Project permissions**: Allows namespaces matching `kigawa-net*` plus `gpu-operator`, `sm-operator-system`, `tidb-system`, `onemc-rpgcore`, `arc-systems`, `arc-runners`
- **Source repos**: `https://github.com/kigawa-net/*`, `oci://ghcr.io/actions/actions-runner-controller-charts`, Helm repos for KubeRay and NVIDIA
- **Sync waves**: `arc-controller` deploys at wave `-1` (before runners), `arc-secret` at wave `0`

## Main Components

### Keruta (`keruta/`)
Session management and workspace system. Three environments:
- `dev/` → namespace `kigawa-net-keruta-dev`
- `main/` → namespace `kigawa-net-keruta-main`
- `beta/` → ingress only (no dedicated deployments)

Services in each full environment:
- **ktse**: Spring Boot backend. Connects to MariaDB (`mariadb-ktse`), ZooKeeper (`zookeeper-ktse:2181`), and TiDB. Validates JWTs against Keycloak (`https://user.kigawa.net/realms/develop`).
- **ktcl-front**: Node.js frontend. Issues JWTs for the `keruta` audience; authenticates via Keycloak.
- **ktcl-k8s**: Manages sandbox K8s jobs in the `kigawa-net-keruta-dev-sandbox` namespace.
- **kicl-web**: Additional web component.
- **mariadb-ktse** / **mariadb-k8s**: MariaDB operator instances (k8s.mariadb.com CRDs).
- **zookeeper-ktse**: ZooKeeper cluster (3 replicas).

Ingress routes (dev): `keruta-dev.kigawa.net`, `ktse-dev.kigawa.net`, `ktcl-k8s-dev.kigawa.net`, `kicl-web-dev.kigawa.net`

### LP (`lp/main/`)
Portfolio/landing page. Namespace: `kigawa-net-lp-main`. Keycloak realm: `kigawa-net`.

### Fonsole (`fonsole/`)
Backup management system. Namespace: `fonsole`. `fomage` service connects to MongoDB at `mongo-svc.fonsole.svc.cluster.local:27017`. Currently scaled to 0 replicas.

### Nextcloud (`nextcloud/`)
Deployed via both raw manifests and a Helm chart (v9.0.3). Namespace: `kigawa-net-nextcloud`. Uses Helm-managed MariaDB and 64Gi `rook-cephfs` for persistence.

### MAAS (`maas/`)
Metal as a Service. Namespace: `kigawa-net-maas`. PostgreSQL 14 StatefulSet with 20Gi `rook-cephfs`.

### Diver-MC (`diver-mc/`)
Minecraft server (Spigot 1.20.6, Java 21). StatefulSet, currently scaled to 0 replicas. Uses manual PV/PVC.

### TiDB (`apps/tidb/`)
Distributed SQL. Namespace: `tidb-system`. Deployed via Helm (operator + CRDs separately). CRD installation uses `ServerSideApply: true`.

### ARC (`arc/`, `apps/arc-controller-app.yml`, `apps/arc-runners-onemc-app.yml`, `apps/arc-secret-app.yml`)
GitHub Actions Runner Controller。OneServerMC org 向けのセルフホストランナーを提供。
- **Controller**: namespace `arc-systems`、Helm chart `gha-runner-scale-set-controller`
- **Runners**: namespace `arc-runners`、`runs-on: arc-runner-set` で参照、dind 有効
- **Secret**: `arc/github-secret-bws.yml` — GitHub App 認証 (app_id / installation_id / private_key)
- 新しい namespace に追加する場合は `bitwarden-sync-crn.yaml` の `TARGET_NAMESPACES` にも追記

### OneServerMC (`apps/one-project.yml`, `apps/rpgcore-dev-app.yml`)
OneServerMC 向け AppProject `one`。namespace `onemc-*` と `https://github.com/OneServerMC/*` を許可。
- **RpgCore dev**: `k8s/overlays/dev` を `onemc-rpgcore` にデプロイ

### Bitwarden / Secret Provider (`kigawa-system/secret-provider/`, `apps/bitwarden-sm-operator-app.yml`)
Bitwarden Secrets Manager operator syncs secrets into each namespace via `BitwardenSecret` CRDs. Organization ID: `a2b57f3d-6e2b-4467-b499-b31e00bfd804`. Each namespace requires a `bitwarden-sec` secret containing the auth token.

`bitwarden-sync-crn.yaml` CronJob (5分ごと) が `kigawa-system` の `bitwarden-sec` を各 namespace に同期。新しい namespace を追加する際は `TARGET_NAMESPACES` リストに追記する。

## Secret Management Pattern

Secrets are **not stored in git**. Each service has a `BitwardenSecret` resource (kind: `k8s.bitwarden.com/v1`) that maps Bitwarden secret IDs to Kubernetes secret keys. The operator syncs these automatically.

To manually create secrets (if operator is unavailable):
```bash
kubectl create secret generic <name> --from-literal=<key>="<value>" -n <namespace>
```

## Deploying Changes

```bash
# Dry-run validate before committing
kubectl apply --dry-run=client -f <manifest-file>

# Check sync status
argocd app list
argocd app get kigawa-net-keruta-dev-app
```

## Image Registry & Tagging

- Registry: `harbor.kigawa.net`
- Paths: `library/<service>` (public/internal) or `private/<service>` (private)
- Tag format:
  - Dev: `develop-<commit-sha>` with `imagePullPolicy: Always`
  - Production: `main-<commit-sha>` with `imagePullPolicy: IfNotPresent`

## Networking

- Ingress class: `haproxy`
- Base domain: `kigawa.net`; dev subdomains follow `*-dev.kigawa.net`
- Identity provider: `user.kigawa.net` (Keycloak)

## Storage Classes

- `rook-cephfs`: Shared filesystem — used for databases, Nextcloud, MAAS
- `rook-ceph-rbd`: Block device — used for MariaDB operator instances in Keruta

## Namespace Organization

| Namespace | Contents |
|-----------|----------|
| `argocd` | ArgoCD |
| `kigawa-net-keruta-dev` | Keruta development |
| `kigawa-net-keruta-main` | Keruta production |
| `kigawa-net-lp-main` | Landing page |
| `kigawa-net-nextcloud` | Nextcloud |
| `kigawa-net-maas` | MAAS |
| `kigawa-net-secret-provider` | Bitwarden sync RBAC |
| `tidb-system` | TiDB operator + CRDs |
| `sm-operator-system` | Bitwarden SM operator |
| `fonsole` | Fonsole backup system |
| default | Diver-MC Minecraft |
| `arc-systems` | ARC controller |
| `arc-runners` | ARC self-hosted runners (OneServerMC) |
| `onemc-rpgcore` | RpgCore dev (Minecraft Paper plugin) |