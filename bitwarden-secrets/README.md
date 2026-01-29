# Bitwarden Secrets Manager Operator セットアップ

このディレクトリには、公式の Bitwarden Secrets Manager Operator の設定が含まれています。

## 🎯 アーキテクチャ

```
Bitwarden Secrets Manager (Cloud/Self-hosted)
    ↓ API
Bitwarden SM Operator (sm-operator-system)
    ↓ Watch BitwardenSecret CRD
Kubernetes Secrets (自動作成)
```

## 📋 セットアップ手順

### 1. Bitwarden Secrets Manager で準備

#### 1.1 Secret を作成

Organization → Secrets Manager で以下を作成:

| Secret Name | Value | 用途 |
|-------------|-------|------|
| `keruta-dev-tidb-user` | TiDB ユーザー名 | Keruta Dev |
| `keruta-dev-tidb-pass` | TiDB パスワード | Keruta Dev |
| `keruta-dev-ktcl-front-private-key` | JWT 秘密鍵 | Keruta Frontend |
| `fonsole-mongo-user` | MongoDB ユーザー名 | Fonsole |
| `fonsole-mongo-pass` | MongoDB パスワード | Fonsole |

**各 Secret の UUID をコピー**（右上の ID ボタン）

#### 1.2 Machine Account を作成

1. Organization Settings → Machine Accounts
2. 新規作成: `kigawa-net-k8s-operator`
3. **Access Token をコピー**
4. 作成した Secret へのアクセス権を付与

#### 1.3 Organization ID を取得

Organization Settings の URL から取得:
```
https://vault.bitwarden.com/organizations/<organization-id>/...
```

### 2. Kubernetes に認証情報を登録

```bash
# Namespace は自動作成されるので、まず Operator をデプロイ
# その後、認証トークンを登録
kubectl create secret generic bw-auth-token \
  --from-literal=token="<your-machine-account-token>" \
  --namespace=sm-operator-system
```

⚠️ **重要**: このコマンドは履歴に残るので、実行後 `history -c` で削除推奨

### 3. BitwardenSecret マニフェストを編集

各ファイルで以下を設定:

**全ファイル共通:**
- `spec.organizationId`: Organization ID を設定

**keruta/dev/secrets/tidb-bitwarden-secret.yaml**
- `bwSecretId`: 2箇所（user, pass の UUID）

**keruta/dev/secrets/ktcl-front-bitwarden-secret.yaml**
- `bwSecretId`: 1箇所（private-key の UUID）

**fonsole/secrets/mongo-bitwarden-secret.yaml**
- `bwSecretId`: 2箇所（user, pass の UUID）

### 4. Git にコミット & デプロイ

```bash
git add apps/bitwarden-sm-operator-app.yml bitwarden-secrets/ \
        keruta/dev/secrets/*bitwarden-secret.yaml \
        fonsole/secrets/*bitwarden-secret.yaml

git commit -m "Add Bitwarden Secrets Manager Operator

- Deploy official Bitwarden sm-operator
- Configure BitwardenSecret CRDs for tidb, ktcl-front, mongo

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push origin main
```

### 5. 動作確認

```bash
# Operator が起動しているか
kubectl get deployment -n sm-operator-system

# BitwardenSecret の状態確認
kubectl get bitwardensecret -A

# Secret が自動作成されているか
kubectl get secret tidb -n kigawa-net-keruta-dev
kubectl get secret ktcl-front -n kigawa-net-keruta-dev
kubectl get secret mongo -n fonsole

# Secret の内容確認
kubectl get secret tidb -n kigawa-net-keruta-dev -o yaml
```

## 🔍 トラブルシューティング

### Operator が起動しない

```bash
# Pod の状態確認
kubectl get pod -n sm-operator-system

# ログ確認
kubectl logs -n sm-operator-system -l app.kubernetes.io/name=sm-operator -f
```

### BitwardenSecret が Secret を作成しない

```bash
# BitwardenSecret の詳細確認
kubectl describe bitwardensecret tidb-secret -n kigawa-net-keruta-dev

# Operator のログ
kubectl logs -n sm-operator-system -l app.kubernetes.io/name=sm-operator | grep tidb
```

**よくあるエラー:**
- `authentication failed`: Access Token が間違っている
- `secret not found`: UUID が間違っている、または Machine Account に権限がない
- `organization not found`: Organization ID が間違っている

### Secret の値が更新されない

デフォルトの同期間隔は 300秒（5分）です。即座に同期したい場合:

```bash
# BitwardenSecret を再作成
kubectl delete bitwardensecret tidb-secret -n kigawa-net-keruta-dev
kubectl apply -f keruta/dev/secrets/tidb-bitwarden-secret.yaml
```

または、Operator を再起動:
```bash
kubectl rollout restart deployment -n sm-operator-system
```

## 🔄 Secret の更新

1. Bitwarden Secrets Manager で Secret の値を更新
2. 自動的に同期される（設定した間隔で）
3. Pod は Secret の変更を検知して再起動（deployment の設定による）

## 🔒 セキュリティのベストプラクティス

1. **最小権限の原則**
   - Machine Account には必要な Secret のみアクセス権を付与
   - Project 単位でアクセス制御

2. **Token のローテーション**
   - 定期的に Machine Account Token を再生成
   - 古い Token は削除

3. **監査ログ**
   - Bitwarden の監査ログで Secret アクセスを追跡
   - Kubernetes Audit Log を有効化

4. **Network Policy**
   - Operator から Bitwarden API へのアウトバウンド通信のみ許可

## 📚 参考リンク

- [Official Documentation](https://bitwarden.com/help/secrets-manager-kubernetes-operator/)
- [Helm Chart](https://github.com/bitwarden/sm-kubernetes)
- [BitwardenSecret CRD Spec](https://github.com/bitwarden/sm-kubernetes/blob/main/config/crd/bases/k8s.bitwarden.com_bitwardensecrets.yaml)
