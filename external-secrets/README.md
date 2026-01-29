# External Secrets Operator + Bitwarden セットアップ

このディレクトリには、External Secrets Operator (ESO) と Bitwarden を使用して Kubernetes Secret を管理するための設定が含まれています。

## アーキテクチャ

```
Bitwarden Vault (外部)
    ↓ API
Bitwarden SDK Server (Pod)
    ↓ HTTP
External Secrets Operator
    ↓ 同期
Kubernetes Secrets
```

## セットアップ手順

### 1. Bitwarden の準備

#### 1.1 API 認証情報の取得

1. [Bitwarden Web Vault](https://vault.bitwarden.com) にログイン
2. Settings → Security → Keys
3. "View API Key" をクリック
4. `client_id` と `client_secret` をコピー

#### 1.2 Bitwarden に Secret を登録

各 Secret 用のアイテムを作成します：

**Keruta Dev TiDB:**
- 項目名: `keruta-dev-tidb-user`
  - パスワード: TiDB のユーザー名
- 項目名: `keruta-dev-tidb-pass`
  - パスワード: TiDB のパスワード

**Keruta Dev Frontend:**
- 項目名: `keruta-dev-ktcl-front-private-key`
  - Notes: JWT 署名用の秘密鍵（長い場合）
  - または パスワード: 短い鍵の場合

**Fonsole MongoDB:**
- 項目名: `fonsole-mongo-user`
  - パスワード: MongoDB のユーザー名
- 項目名: `fonsole-mongo-pass`
  - パスワード: MongoDB のパスワード

### 2. Kubernetes への適用

#### 2.1 Bitwarden 認証情報 Secret の作成

```bash
# Bitwarden API 認証情報を登録
kubectl create namespace external-secrets-system

kubectl create secret generic bitwarden-cli-credentials \
  --from-literal=BW_CLIENTID="user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  --from-literal=BW_CLIENTSECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
  --from-literal=BW_PASSWORD="your-master-password" \
  --namespace=external-secrets-system
```

⚠️ **セキュリティ注意**: この Secret は絶対に Git にコミットしないでください！

#### 2.2 ArgoCD で ESO をデプロイ

```bash
# 既に apps/external-secrets-app.yml が作成されているため、
# ArgoCD が自動的に同期します

# 手動で確認する場合:
kubectl get application -n argocd | grep external-secrets
argocd app sync external-secrets-operator
argocd app sync external-secrets-config
```

#### 2.3 デプロイ確認

```bash
# ESO のインストール確認
kubectl get deployment -n external-secrets-system

# 期待される出力:
# external-secrets
# external-secrets-cert-controller
# external-secrets-webhook
# bitwarden-sdk-server

# ClusterSecretStore の確認
kubectl get clustersecretstore
# NAME        AGE   STATUS   READY
# bitwarden   1m    Valid    True

# ExternalSecret の確認
kubectl get externalsecret -A

# Secret が自動作成されているか確認
kubectl get secret tidb -n kigawa-net-keruta-dev
kubectl get secret ktcl-front -n kigawa-net-keruta-dev
kubectl get secret mongo -n fonsole
```

### 3. トラブルシューティング

#### ESO が Secret を同期しない場合

```bash
# ExternalSecret のステータス確認
kubectl describe externalsecret tidb -n kigawa-net-keruta-dev

# ESO のログ確認
kubectl logs -n external-secrets-system deployment/external-secrets

# Bitwarden SDK Server のログ確認
kubectl logs -n external-secrets-system deployment/bitwarden-sdk-server
```

#### Bitwarden SDK Server が起動しない場合

```bash
# Pod の状態確認
kubectl get pod -n external-secrets-system -l app=bitwarden-sdk-server

# 詳細ログ
kubectl logs -n external-secrets-system -l app=bitwarden-sdk-server --tail=100
```

よくあるエラー:
- `Authentication failed`: BW_CLIENTID, BW_CLIENTSECRET, BW_PASSWORD が正しいか確認
- `Item not found`: Bitwarden Vault に該当する項目が存在するか確認

## 新しい Secret の追加方法

1. Bitwarden Vault に新しいアイテムを作成
2. ExternalSecret マニフェストを作成:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-new-secret
  namespace: my-namespace
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden
    kind: ClusterSecretStore
  target:
    name: my-new-secret
    creationPolicy: Owner
  data:
    - secretKey: my-key
      remoteRef:
        key: bitwarden-item-name  # Bitwarden の項目名
```

3. Git にコミットして ArgoCD に同期

## セキュリティベストプラクティス

1. **Bitwarden 認証情報の保護**
   - `bitwarden-cli-credentials` Secret は手動作成のみ
   - Git にコミットしない
   - RBAC で適切にアクセス制限

2. **Secret のローテーション**
   - Bitwarden で Secret を更新
   - ESO が自動的に同期（refreshInterval に基づく）
   - または手動で強制同期: `kubectl annotate externalsecret <name> force-sync=$(date +%s) -n <namespace>`

3. **監査ログ**
   - Bitwarden の監査ログで Secret アクセスを追跡
   - Kubernetes の RBAC 監査ログを有効化

## 参考リンク

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [Bitwarden API Documentation](https://bitwarden.com/help/api/)
- [Bitwarden SDK Server](https://github.com/lazyorangejs/bitwarden-sdk-server)
