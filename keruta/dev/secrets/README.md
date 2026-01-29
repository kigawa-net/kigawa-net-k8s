# Keruta Dev Secrets

このディレクトリには Keruta Development 環境で使用する Secret の ExternalSecret 定義があります。

## 使用する前に

1. **Bitwarden に Secret を登録**（どちらの方式でも必要）

2. **使用する方式を選択**
   - **Secrets Manager**: `secretStoreRef.name: bitwarden-secretsmanager` を使用
   - **CLI Webhook**: `secretStoreRef.name: bitwarden-cli` を使用

## Secrets Manager 方式の場合

### Bitwarden Secrets Manager での設定

1. Organization の Secrets Manager にアクセス
2. 以下の Secret を作成:
   - `keruta-dev-tidb-user` → 値: TiDB ユーザー名
   - `keruta-dev-tidb-pass` → 値: TiDB パスワード
   - `keruta-dev-ktcl-front-private-key` → 値: JWT 秘密鍵

3. 各 Secret の **UUID をコピー**

4. ExternalSecret で UUID を指定:
   ```yaml
   remoteRef:
     key: "339062b8-a5a1-4303-bf1d-b1920146a622"  # Secret の UUID
   ```

## 適用方法

ExternalSecret を適用すると、自動的に Kubernetes Secret が作成されます:

```bash
# ExternalSecret を適用（ArgoCD が自動適用）
kubectl get externalsecret -n kigawa-net-keruta-dev

# 作成された Secret を確認
kubectl get secret tidb -n kigawa-net-keruta-dev
kubectl get secret ktcl-front -n kigawa-net-keruta-dev

# Secret の内容確認
kubectl get secret tidb -n kigawa-net-keruta-dev -o yaml
```

## トラブルシューティング

```bash
# ExternalSecret のステータス確認
kubectl describe externalsecret tidb -n kigawa-net-keruta-dev

# ESO のログ
kubectl logs -n external-secrets-system deployment/external-secrets -f
```
