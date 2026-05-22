# kigawa-net-k8s

kigawa.net インフラの Kubernetes マニフェストリポジトリです。ArgoCD による GitOps で管理されており、`main` ブランチへのマージが自動デプロイをトリガーします。

---

## アーキテクチャ概要

```
GitHub (main branch)
    └── ArgoCD (apps/apps-app.yml)
            └── apps/ 配下の Application リソースを再帰的に同期
                    ├── keruta-dev-app.yml  → keruta/dev/
                    ├── keruta-main.yml     → keruta/main/
                    ├── lp-main.yml         → lp/main/
                    └── ... (各サービスの Application)
```

- **ルートアプリ**: `apps/apps-app.yml` — すべての子 Application を管理し、`kigawa-net` AppProject を定義
- **同期ポリシー**: 全アプリで自動同期 + prune 有効。selfHeal は MAAS と TiDB のみ有効
- **プロジェクト権限**: `kigawa-net*` にマッチする全 Namespace、および `https://github.com/kigawa-net/*` 配下のリポジトリを許可

---

## ディレクトリ構成

```
kigawa-net-k8s/
├── apps/               # ArgoCD Application リソース群 + ルートアプリ
│   ├── apps-app.yml    # ルート Application (ArgoCD にこれだけ登録する)
│   ├── tidb/           # TiDB Helm アプリ
│   └── vllm/           # vLLM アプリ
├── keruta/             # Keruta セッション管理システム
│   ├── dev/            # 開発環境
│   └── main/           # 本番環境
├── lp/main/            # ランディングページ
├── fonsole/            # バックアップ管理システム
├── nextcloud/          # Nextcloud
├── maas/               # Metal as a Service
├── diver-mc/           # Minecraft サーバー
├── mc/                 # その他 Minecraft 関連
└── kigawa-system/      # 共通システムリソース (Bitwarden Secret Provider 等)
```

---

## 運用フロー

### 変更のデプロイ手順

1. ブランチを切って変更をコミット
2. コミット前にドライランで検証:
   ```bash
   kubectl apply --dry-run=client -f <manifest-file>
   ```
3. `main` ブランチへマージ → ArgoCD が自動的に同期・デプロイ
4. 同期状態の確認:
   ```bash
   argocd app list
   argocd app get <app-name>
   ```

> **注意**: `main` へのマージは即時デプロイを意味します。本番影響がある変更は十分に検証してからマージしてください。

---

## 新しいアプリの追加方法

1. **マニフェストディレクトリを作成**: `<service-name>/` または `<service-name>/<env>/`
2. **ArgoCD Application リソースを作成**: `apps/<service-name>-app.yml`
   - `project: kigawa-net` を指定
   - `namespace` は命名規則に従う (後述)
   - `syncPolicy.automated.prune: true` を設定
3. `apps/apps-app.yml` は `apps/` を再帰的に読むため、追加ファイルだけで自動認識される

### Application リソースの最小テンプレート

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kigawa-net-<service>-app
  namespace: argocd
spec:
  project: kigawa-net
  source:
    repoURL: https://github.com/kigawa-net/kigawa-net-k8s.git
    targetRevision: main
    path: <service>/
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: kigawa-net-<service>
  syncPolicy:
    automated:
      prune: true
      selfHeal: false
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
```

---

## 命名規則

### Namespace

| 種別 | パターン | 例 |
|------|---------|-----|
| サービス (本番) | `kigawa-net-<service>` | `kigawa-net-lp-main` |
| サービス (開発) | `kigawa-net-<service>-dev` | `kigawa-net-keruta-dev` |
| システム共通 | そのまま | `argocd`, `tidb-system`, `sm-operator-system` |

### ArgoCD Application 名

`kigawa-net-<service>-<env>-app` 形式。例: `kigawa-net-keruta-dev-app`

### ディレクトリ

- 環境別に分ける場合: `<service>/dev/`, `<service>/main/`
- 環境が1つの場合: `<service>/main/` または `<service>/`

---

## シークレット管理

**シークレットは Git に保存しません。**

Bitwarden Secrets Manager オペレーターが各 Namespace に自動同期します。

### 構成

- オペレーター Namespace: `sm-operator-system`
- Organization ID: `a2b57f3d-6e2b-4467-b499-b31e00bfd804`
- 各 Namespace に `bitwarden-sec` という Secret (認証トークン) が必要

### BitwardenSecret リソースの例

```yaml
apiVersion: k8s.bitwarden.com/v1
kind: BitwardenSecret
metadata:
  name: my-secret
  namespace: kigawa-net-<service>
spec:
  organizationId: a2b57f3d-6e2b-4467-b499-b31e00bfd804
  secretName: my-k8s-secret
  map:
    - bwSecretId: "<Bitwarden Secret UUID>"
      secretKeyName: my-key
  authToken:
    secretName: bitwarden-sec
    secretKey: token
```

### オペレーターが利用できない場合の手動作成

```bash
kubectl create secret generic <name> \
  --from-literal=<key>="<value>" \
  -n <namespace>
```

---

## イメージレジストリ・タグ規則

- **レジストリ**: `harbor.kigawa.net`
- **パス**:
  - 公開/内部: `harbor.kigawa.net/library/<service>`
  - プライベート: `harbor.kigawa.net/private/<service>`

| 環境 | タグ形式 | imagePullPolicy |
|------|---------|-----------------|
| 開発 | `develop-<commit-sha>` | `Always` |
| 本番 | `main-<commit-sha>` | `IfNotPresent` |

---

## ネットワーク・イングレス規則

- **Ingress クラス**: `haproxy`
- **ベースドメイン**: `kigawa.net`
- **開発サブドメイン**: `<service>-dev.kigawa.net`
- **本番サブドメイン**: `<service>.kigawa.net`
- **認証**: `user.kigawa.net` (Keycloak)

---

## ストレージクラス

| クラス | 用途 |
|--------|------|
| `rook-cephfs` | 共有ファイルシステム。データベース (PostgreSQL 等)、Nextcloud、MAAS |
| `rook-ceph-rbd` | ブロックデバイス。Keruta の MariaDB オペレーターインスタンス |

---

## Namespace 一覧

| Namespace | 用途 |
|-----------|------|
| `argocd` | ArgoCD |
| `kigawa-net-keruta-dev` | Keruta 開発環境 |
| `kigawa-net-keruta-main` | Keruta 本番環境 |
| `kigawa-net-lp-main` | ランディングページ |
| `kigawa-net-nextcloud` | Nextcloud |
| `kigawa-net-maas` | MAAS |
| `kigawa-net-secret-provider` | Bitwarden 同期 RBAC |
| `tidb-system` | TiDB オペレーター + CRD |
| `sm-operator-system` | Bitwarden SM オペレーター |
| `fonsole` | Fonsole バックアップシステム |
| `default` | Diver-MC Minecraft |

---

## 主要コンポーネント

### Keruta (`keruta/`)
セッション管理・ワークスペースシステム。

| サービス | 説明 |
|---------|------|
| `ktse` | Spring Boot バックエンド。MariaDB・ZooKeeper・TiDB に接続 |
| `ktcl-front` | Node.js フロントエンド。Keycloak 認証 |
| `ktcl-k8s` | サンドボックス K8s ジョブ管理 |
| `kicl-web` | Web コンポーネント |
| `mariadb-ktse` / `mariadb-k8s` | MariaDB オペレーターインスタンス |
| `zookeeper-ktse` | ZooKeeper クラスター (3 レプリカ) |

### その他

| コンポーネント | Namespace | 説明 |
|--------------|-----------|------|
| LP | `kigawa-net-lp-main` | ポートフォリオ・ランディングページ |
| Fonsole | `fonsole` | バックアップ管理 (現在 0 レプリカ) |
| Nextcloud | `kigawa-net-nextcloud` | Helm v9.0.3、64Gi rook-cephfs |
| MAAS | `kigawa-net-maas` | Metal as a Service、PostgreSQL 14 |
| Diver-MC | `default` | Minecraft (現在 0 レプリカ) |
| TiDB | `tidb-system` | 分散 SQL、Helm デプロイ |
