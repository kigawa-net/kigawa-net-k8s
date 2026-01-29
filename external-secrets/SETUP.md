# Bitwarden Secrets Manager セットアップガイド

このガイドでは、Bitwarden Secrets Manager を使用して External Secrets Operator をセットアップします。

## 📋 前提条件

- Bitwarden の **Business** または **Enterprise** プラン
- Organization が作成済み
- kubectl でクラスタにアクセス可能

## 🔐 ステップ 1: Bitwarden Secrets Manager で Secret を作成

### 1.1 Secrets Manager にアクセス

1. [Bitwarden Web Vault](https://vault.bitwarden.com) にログイン
2. Organization を選択
3. **Secrets Manager** タブをクリック

### 1.2 Project を作成（オプションだが推奨）

1. "Projects" → "New Project"
2. Project name: `kigawa-net-k8s`
3. 作成した Project ID をメモ

### 1.3 Secret を作成

以下の 5 つの Secret を作成します：

| Secret Name | Value | 説明 |
|-------------|-------|------|
| `keruta-dev-tidb-user` | TiDB のユーザー名 | Keruta Dev 用 DB 認証 |
| `keruta-dev-tidb-pass` | TiDB のパスワード | Keruta Dev 用 DB 認証 |
| `keruta-dev-ktcl-front-private-key` | JWT 秘密鍵（複数行可） | Frontend 認証用 |
| `fonsole-mongo-user` | MongoDB のユーザー名 | Fonsole 用 DB 認証 |
| `fonsole-mongo-pass` | MongoDB のパスワード | Fonsole 用 DB 認証 |

**各 Secret の作成手順:**
1. "Secrets" → "New Secret"
2. Name と Value を入力
3. Project に紐付け（作成した場合）
4. Save
5. **UUID をコピー**（Secret 詳細画面の右上、ID アイコンをクリック）

### 1.4 UUID の例

UUID は以下のような形式です：
```
339062b8-a5a1-4303-bf1d-b1920146a622
```

## 🔑 ステップ 2: Machine Account を作成

### 2.1 Machine Account の作成

1. Organization Settings → **Machine Accounts**
2. "New Machine Account"
3. Name: `kigawa-net-k8s-eso`
4. "Create Machine Account"

### 2.2 Access Token の取得

1. 作成した Machine Account を開く
2. "New Access Token"
3. Token name: `k8s-cluster-prod`
4. **Access Token をコピー**（一度しか表示されません！）

### 2.3 権限の設定

1. Machine Account に先ほど作成した Project へのアクセス権を付与
2. または個別の Secret へのアクセス権を付与

## ⚙️ ステップ 3: ClusterSecretStore の設定

### 3.1 organizationID を取得

1. Organization Settings を開く
2. URL から Organization ID をコピー
   ```
   https://vault.bitwarden.com/organizations/<organization-id>/...
   ```

### 3.2 bitwarden-secretsmanager-store.yaml を編集

```bash
vi external-secrets/stores/bitwarden-secretsmanager-store.yaml
```

以下の部分を編集：
```yaml
# Organization ID を設定
organizationID: "your-organization-id"  # ← 実際の ID に置換
```

## 🔧 ステップ 4: Kubernetes に設定を適用

### 4.1 Namespace 作成

```bash
kubectl create namespace external-secrets-system
```

### 4.2 Access Token を Secret として登録

```bash
kubectl create secret generic bitwarden-secrets-manager-token \
  --from-literal=token="<your-machine-account-access-token>" \
  --namespace=external-secrets-system
```

⚠️ **重要**: このコマンドは履歴に残るので、実行後は `history -d <番号>` で削除することを推奨

### 4.3 ExternalSecret の UUID を更新

各 ExternalSecret ファイルの `<uuid-of-xxx-secret>` を実際の UUID に置換：

**keruta/dev/secrets/tidb-external-secret.yaml**
```yaml
data:
  - secretKey: user
    remoteRef:
      key: "339062b8-a5a1-4303-bf1d-b1920146a622"  # ← keruta-dev-tidb-user の UUID
  - secretKey: pass
    remoteRef:
      key: "44a073c9-b6b2-4414-c2ce-c2031257b733"  # ← keruta-dev-tidb-pass の UUID
```

**keruta/dev/secrets/ktcl-front-external-secret.yaml**
```yaml
data:
  - secretKey: private-key
    remoteRef:
      key: "55b184da-c7c3-5525-d3df-d3142368c844"  # ← keruta-dev-ktcl-front-private-key の UUID
```

**fonsole/secrets/mongo-external-secret.yaml**
```yaml
data:
  - secretKey: user
    remoteRef:
      key: "66c295eb-d8d4-6636-e4e0-e4253479d955"  # ← fonsole-mongo-user の UUID
  - secretKey: pass
    remoteRef:
      key: "77d3a6fc-e9e5-7747-f5f1-f5364580ea66"  # ← fonsole-mongo-pass の UUID
```

## 📦 ステップ 5: Git にコミット & デプロイ

### 5.1 変更を確認

```bash
git status
git diff
```

### 5.2 コミット

```bash
git add .gitignore apps/external-secrets-app.yml external-secrets/ keruta/dev/secrets/ fonsole/secrets/
git commit -m "Add External Secrets Operator with Bitwarden Secrets Manager

- Configure Bitwarden Secrets Manager as secrets backend
- Add ExternalSecrets for tidb, ktcl-front, mongo
- Update organizationID and secret UUIDs

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
git push origin main
```

### 5.3 ArgoCD で同期

```bash
# 自動同期を待つ、または手動で同期
argocd app sync external-secrets-operator
argocd app sync external-secrets-config
```

## ✅ ステップ 6: 動作確認

### 6.1 ESO のデプロイ確認

```bash
# ESO の Pod が起動しているか
kubectl get deployment -n external-secrets-system

# 期待される Pod:
# - external-secrets
# - external-secrets-cert-controller
# - external-secrets-webhook
```

### 6.2 ClusterSecretStore の確認

```bash
kubectl get clustersecretstore bitwarden-secretsmanager

# STATUS が Valid、READY が True であることを確認
```

エラーがある場合:
```bash
kubectl get clustersecretstore bitwarden-secretsmanager -o yaml
```

### 6.3 ExternalSecret の確認

```bash
# すべての ExternalSecret を確認
kubectl get externalsecret -A

# 個別に確認
kubectl describe externalsecret tidb -n kigawa-net-keruta-dev
kubectl describe externalsecret ktcl-front -n kigawa-net-keruta-dev
kubectl describe externalsecret mongo -n fonsole
```

STATUS が `SecretSynced` であることを確認

### 6.4 Secret が作成されているか確認

```bash
# Secret が自動作成されているか
kubectl get secret tidb -n kigawa-net-keruta-dev
kubectl get secret ktcl-front -n kigawa-net-keruta-dev
kubectl get secret mongo -n fonsole

# Secret の内容確認（base64 デコード）
kubectl get secret tidb -n kigawa-net-keruta-dev -o jsonpath='{.data.user}' | base64 -d
kubectl get secret tidb -n kigawa-net-keruta-dev -o jsonpath='{.data.pass}' | base64 -d
```

## 🔍 トラブルシューティング

### ClusterSecretStore が Valid にならない

```bash
# ClusterSecretStore の詳細確認
kubectl describe clustersecretstore bitwarden-secretsmanager

# ESO のログ確認
kubectl logs -n external-secrets-system deployment/external-secrets -f
```

**よくあるエラー:**
- `authentication failed`: Access Token が間違っている
- `organization not found`: organizationID が間違っている
- `insufficient permissions`: Machine Account に権限がない

### ExternalSecret が SecretSynced にならない

```bash
# ExternalSecret の Events を確認
kubectl describe externalsecret tidb -n kigawa-net-keruta-dev

# ESO のログ
kubectl logs -n external-secrets-system deployment/external-secrets -f | grep tidb
```

**よくあるエラー:**
- `secret not found`: UUID が間違っている
- `access denied`: Machine Account に Secret へのアクセス権がない

### Secret の値が正しくない

1. Bitwarden Secrets Manager で Secret の値を確認
2. ExternalSecret の `property` が正しいか確認（通常は `"value"`）
3. Secret を削除して再同期:
   ```bash
   kubectl delete secret tidb -n kigawa-net-keruta-dev
   kubectl annotate externalsecret tidb force-sync=$(date +%s) -n kigawa-net-keruta-dev
   ```

## 🔄 Secret の更新方法

### Bitwarden で Secret を更新した場合

ExternalSecret は自動的に同期されます（`refreshInterval: 1h`）。

即座に同期したい場合:
```bash
kubectl annotate externalsecret tidb force-sync=$(date +%s) -n kigawa-net-keruta-dev
```

### 新しい Secret を追加する場合

1. Bitwarden Secrets Manager で新しい Secret を作成
2. UUID をコピー
3. ExternalSecret マニフェストを作成/更新
4. Git にコミット & プッシュ

## 🔒 セキュリティのベストプラクティス

1. **Machine Account Token の管理**
   - Token は安全に保管
   - 定期的にローテーション
   - 不要になったら削除

2. **最小権限の原則**
   - Machine Account には必要最小限の権限のみ付与
   - Project 単位でアクセス制御

3. **監査ログ**
   - Bitwarden の監査ログで Secret アクセスを追跡
   - Kubernetes の Audit Log を有効化

4. **Network Policy**
   - ESO からのアウトバウンド通信のみ許可

## 📚 参考リンク

- [External Secrets Operator - Bitwarden Secrets Manager](https://external-secrets.io/main/provider/bitwarden-secrets-manager/)
- [Bitwarden Secrets Manager Documentation](https://bitwarden.com/help/secrets-manager-overview/)
- [Bitwarden Machine Accounts](https://bitwarden.com/help/machine-accounts/)
