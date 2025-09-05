# Keruta Kubernetes Deployment

このディレクトリにはKerutaアプリケーションのKubernetesデプロイメント設定が含まれています。

## デプロイメント手順

### 1. Secretの作成

#### MongoDB Secret
```bash
kubectl create secret generic mongo \
  --from-literal=user="admin" \
  --from-literal=pass="your-mongodb-password" \
  --namespace=kigawa-net-keruta
```

#### Application Secret
```bash
kubectl create secret generic app-secret \
  --from-literal=secret="your-jwt-secret-key" \
  --namespace=kigawa-net-keruta

kubectl create secret generic app-pass \
  --from-literal=api-password="your-api-password" \
  --from-literal=admin-password="your-admin-password" \
  --namespace=kigawa-net-keruta
```

#### Keycloak Secret
```bash
kubectl create secret generic keycloak \
  --from-literal=secret="your-keycloak-client-secret" \
  --namespace=kigawa-net-keruta
```

#### Coder Secret
```bash
kubectl create secret generic coder \
  --from-literal=session-token="your-coder-session-token" \
  --namespace=kigawa-net-keruta
```

**注意**: Coderセッショントークンは keruta-executor サービスによって24時間ごとに自動更新されます。

### 2. アプリケーションのデプロイ

```bash
kubectl apply -f keruta.yaml
```

## Coder統合設定

Keruta は Coder との統合をサポートしています。以下の環境変数で設定可能です：

### 必須設定
- `CODER_BASE_URL`: CoderインスタンスのURL（例: https://coder.kigawa.net）
- `CODER_SESSION_TOKEN`: Coder認証用のセッショントークン

### オプション設定
- `CODER_ORGANIZATION`: 組織名（デフォルト: default）
- `CODER_USER`: ユーザー名（デフォルト: admin）
- `CODER_DEFAULT_TEMPLATE_ID`: デフォルトテンプレートID
- `CODER_CONNECTION_TIMEOUT`: 接続タイムアウト（ミリ秒、デフォルト: 10000）
- `CODER_READ_TIMEOUT`: 読み取りタイムアウト（ミリ秒、デフォルト: 30000）
- `CODER_ENABLE_SSL_VERIFICATION`: SSL検証の有効化（デフォルト: true）

### Coderセッショントークンの取得方法

1. Coderのwebインターフェースにログイン
2. Settings > Personal Access Tokens に移動
3. 新しいトークンを作成
4. 作成されたトークンを `CODER_SESSION_TOKEN` として設定

## 主要な機能

- セッション管理
- ワークスペースの作成・管理
- Coder REST APIとの統合
- セッション詳細でのワークスペースリンク表示

## トラブルシューティング

### Coder接続エラー
- `CODER_BASE_URL` が正しいことを確認
- `CODER_SESSION_TOKEN` が有効であることを確認
- ネットワーク接続を確認

### 権限エラー
- Coderのユーザーがワークスペース作成権限を持っていることを確認
- 組織の設定を確認