# External Secrets Operator + Bitwarden クイックスタート

## 📋 まず、どちらの方式を使うか決める

| 方式 | 必要なもの | おすすめ度 |
|------|-----------|----------|
| **Bitwarden Secrets Manager** | 有料プラン | ⭐⭐⭐ 安定・公式 |
| **CLI Webhook** | 無料プランでもOK | ⭐⭐ 要 CLI サーバー管理 |

---

## 🔐 方式A: Bitwarden Secrets Manager（推奨）

### ステップ 1️⃣: Bitwarden Secrets Manager で Secret を作成

1. [Bitwarden Web Vault](https://vault.bitwarden.com) にログイン
2. Organization → Secrets Manager
3. 以下の Secret を作成:

| Secret Name | Value |
|-------------|-------|
| `keruta-dev-tidb-user` | TiDB ユーザー名 |
| `keruta-dev-tidb-pass` | TiDB パスワード |
| `keruta-dev-ktcl-front-private-key` | JWT 秘密鍵 |
| `fonsole-mongo-user` | MongoDB ユーザー名 |
| `fonsole-mongo-pass` | MongoDB パスワード |

4. **各 Secret の UUID をコピー**（後で使用）

### ステップ 2️⃣: Machine Account Token を取得

1. Organization Settings → Machine Accounts
2. 新しい Machine Account を作成
3. **Access Token をコピー**

### ステップ 3️⃣: Kubernetes に認証情報を登録

```bash
kubectl create namespace external-secrets-system

kubectl create secret generic bitwarden-secrets-manager-token \
  --from-literal=token="<your-access-token>" \
  --namespace=external-secrets-system
```

### ステップ 4️⃣: ExternalSecret の UUID を更新

```bash
# 各 ExternalSecret ファイルの <uuid-of-xxx-secret> を実際の UUID に置換
vi keruta/dev/secrets/tidb-external-secret.yaml
vi keruta/dev/secrets/ktcl-front-external-secret.yaml
vi fonsole/secrets/mongo-external-secret.yaml

# また、external-secrets/stores/bitwarden-secretsmanager-store.yaml の
# organizationID を設定
vi external-secrets/stores/bitwarden-secretsmanager-store.yaml
```

### ステップ 5️⃣: Git にコミット & デプロイ

```bash
git add .
git commit -m "Setup External Secrets Operator with Bitwarden Secrets Manager"
git push origin main

# ArgoCD が自動同期
argocd app sync external-secrets-operator
argocd app sync external-secrets-config
```

---


### ステップ 5️⃣: Git にコミット & デプロイ

```bash
git add .
git commit -m "Setup External Secrets Operator with Bitwarden CLI Webhook"
git push origin main

# ArgoCD が自動同期
argocd app sync external-secrets-operator
argocd app sync external-secrets-config
```

---

## ✅ 確認

```bash
# ESO が稼働しているか確認
kubectl get deployment -n external-secrets-system

# 期待される Pod:
# - external-secrets
# - external-secrets-cert-controller
# - external-secrets-webhook
# - bitwarden-cli (CLI Webhook 方式の場合のみ)

# ClusterSecretStore の確認
kubectl get clustersecretstore

# Secret が自動作成されたか確認
kubectl get secret tidb -n kigawa-net-keruta-dev
kubectl get secret ktcl-front -n kigawa-net-keruta-dev
kubectl get secret mongo -n fonsole
```

すべて表示されれば **完了** 🎉

---

## 🔍 トラブルシューティング

```bash
# ExternalSecret のステータス確認
kubectl describe externalsecret tidb -n kigawa-net-keruta-dev

# ESO のログ
kubectl logs -n external-secrets-system deployment/external-secrets -f

# CLI Webhook の場合
kubectl logs -n external-secrets-system deployment/bitwarden-cli -f
```

詳細は [README.md](./README.md) および [stores/README.md](./stores/README.md) を参照してください。
