# External Secrets Operator + Bitwarden クイックスタート

## 🚀 3ステップでセットアップ

### ステップ 1️⃣: Bitwarden の準備（5分）

```bash
# 1. Bitwarden Web Vault にログイン
# https://vault.bitwarden.com

# 2. 以下の Secret アイテムを作成:
```

| 項目名 | パスワードフィールド | 説明 |
|--------|---------------------|------|
| `keruta-dev-tidb-user` | TiDB ユーザー名 | Keruta Dev 環境用 |
| `keruta-dev-tidb-pass` | TiDB パスワード | Keruta Dev 環境用 |
| `keruta-dev-ktcl-front-private-key` | JWT 秘密鍵 | Frontend 認証用 |
| `fonsole-mongo-user` | MongoDB ユーザー名 | Fonsole 用 |
| `fonsole-mongo-pass` | MongoDB パスワード | Fonsole 用 |

```bash
# 3. API キーを取得
# Settings → Security → Keys → "View API Key"
# client_id と client_secret をメモ
```

### ステップ 2️⃣: Kubernetes に認証情報を登録（1分）

```bash
# Namespace 作成
kubectl create namespace external-secrets-system

# Bitwarden 認証情報を Secret として作成
kubectl create secret generic bitwarden-cli-credentials \
  --from-literal=BW_CLIENTID="user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  --from-literal=BW_CLIENTSECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
  --from-literal=BW_PASSWORD="your-bitwarden-master-password" \
  --namespace=external-secrets-system
```

⚠️ **重要**: この Secret は絶対に Git にコミットしないこと！

### ステップ 3️⃣: Git にコミット & ArgoCD 同期（2分）

```bash
# 変更をコミット
git add apps/external-secrets-app.yml external-secrets/ keruta/dev/secrets/ fonsole/secrets/
git commit -m "Add External Secrets Operator with Bitwarden integration"
git push origin main

# ArgoCD が自動同期するのを待つ（または手動同期）
argocd app sync external-secrets-operator
argocd app sync external-secrets-config
```

## ✅ 確認

```bash
# ESO が稼働しているか確認
kubectl get deployment -n external-secrets-system
# 期待: external-secrets, bitwarden-sdk-server が Running

# Secret が自動作成されたか確認
kubectl get secret tidb -n kigawa-net-keruta-dev
kubectl get secret ktcl-front -n kigawa-net-keruta-dev
kubectl get secret mongo -n fonsole
```

すべて表示されれば **完了** 🎉

## 🔍 問題が発生した場合

```bash
# ExternalSecret のステータス確認
kubectl describe externalsecret tidb -n kigawa-net-keruta-dev

# ESO のログ
kubectl logs -n external-secrets-system deployment/external-secrets -f

# Bitwarden SDK Server のログ
kubectl logs -n external-secrets-system deployment/bitwarden-sdk-server -f
```

詳細は [README.md](./README.md) を参照してください。
