# ArgoCD の GitHub 認証を GitHub App に置き換えた記録

ArgoCD が GitHub の repo を読めなくなった障害(2026-10-23〜24)の経緯と、恒久対応として導入した GitHub App による認証の手順をまとめます。

> **注意**: このドキュメントには秘密鍵・トークン・個人のメールアドレスを書きません。鍵の実体は Bitwarden にあります(後述「6. 秘密鍵の保管」)。

---

## 1. 経緯(2026-10-23〜24)

- ArgoCD が GitHub の repo からリビジョンを取得できなくなり、次のエラーが出ました。

  ```
  ComparisonError: failed to list refs: authentication required: Invalid username or token
  ```

- 112 アプリのうち 95 アプリで同期が止まりました。
- 原因: `argocd` namespace の repo 認証情報が、固定の Personal Access Token (PAT) でした。
  - 対象は repo-creds `creds-3226016447` と、個別の `repo-*` シークレットです。
  - この PAT が失効していました。
- 公開リポジトリでも、無効なトークンを送ると GitHub は認証エラーで拒否します。そのため、公開 repo であっても同期が止まりました。

---

## 2. 恒久対応: 読み取り専用の GitHub App に置き換え

PAT をやめ、読み取り専用の GitHub App `kigawa-net-argocd` に置き換えました。

| 項目 | 値 |
|------|----|
| App 名 | `kigawa-net-argocd` |
| App ID | `5452250` |
| 権限 | Contents: Read-only、Metadata: Read-only(これ以外は付与しない) |

- ArgoCD は App の秘密鍵から、短命のインストールトークンを自動で発行します。このため、PAT のような期限切れがありません。
- インストール先と Installation ID は次のとおりです。Installation ID は秘密ではありません。

| インストール先 | Installation ID | ArgoCD シークレット名 |
|----------------|-----------------|------------------------|
| kigawa-net | `174732693` | `argocd-ghapp-kigawa-net` |
| kigawa01(個人) | `174734795` | `argocd-ghapp-kigawa01` |
| OneServerMC | `174734699` | `argocd-ghapp-onemc` |

### ArgoCD のシークレットの形

各シークレットは `argocd` namespace に作り、次のラベルを付けます。

- ラベル: `argocd.argoproj.io/secret-type: repo-creds`
- データのキー:

| キー | 値 |
|------|----|
| `type` | `git` |
| `url` | `https://github.com/<組織>`(例: `https://github.com/kigawa-net`) |
| `githubAppID` | App ID |
| `githubAppInstallationID` | その組織の Installation ID |
| `githubAppPrivateKey` | App の秘密鍵(PEM)。**値はリポジトリにも docs にも書かない** |

---

## 3. 新しい組織・repo を足す手順

1. **App をその組織にインストールし、Installation ID を控える。**
   - App は他の組織にもインストールできる設定になっています。
   - 他人の組織にインストールするには、その組織の管理者の承認が必要です。
2. **`argocd-ghapp-<名前>` シークレットを作る。** 鍵のパスは実際のパスに置き換えます。

   ```bash
   kubectl create secret generic argocd-ghapp-<名前> -n argocd \
     --from-literal=type=git \
     --from-literal=url=https://github.com/<組織> \
     --from-literal=githubAppID=5452250 \
     --from-literal=githubAppInstallationID=<Installation ID> \
     --from-file=githubAppPrivateKey=<鍵のパス>

   kubectl label secret argocd-ghapp-<名前> -n argocd \
     argocd.argoproj.io/secret-type=repo-creds
   ```

3. **個別の `repo-*` シークレットにパスワードが残っていないか確認し、残っていれば外す。**
   - 個別の repo シークレットに認証情報があると、組織用の認証情報より優先されます。
   - 外すには次のコマンドを使います。

   ```bash
   kubectl patch secret <repo-*> -n argocd --type merge \
     -p '{"data":{"password":null,"username":null}}'
   ```

4. **反映を待つ。** ArgoCD のキャッシュのため、反映まで最大 3 分かかります。

### 優先順位

- repo-creds は URL の最長一致で選ばれます。
- 具体的な組織の URL(例: `https://github.com/kigawa-net`)が、`https://github.com/` より優先されます。

---

## 4. 診断のコマンド

### ComparisonError の数を数える

```bash
kubectl get applications -n argocd -o json \
  | jq '[.items[] | select(any(.status.conditions[]?; .type == "ComparisonError"))] | length'
```

### repo-server のログを見る

```bash
kubectl logs -n argocd deploy/argocd-repo-server --since=10m | grep -i 'auth' || true
```

### 認証シークレットの一覧を見る(値は出さない)

```bash
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type \
  -o custom-columns=NAME:.metadata.name
```

> **注意**: シークレットの値を表示しないでください。`kubectl get secret -o yaml`、`-o json`、`describe` の出力には `data` の値(base64 でも秘密です)が含まれます。値の確認が必要な場合も、キーの有無だけを確認します。
> 同じ理由で、設定ファイルの中身を出力する診断は行わないでください。

---

## 5. 残っている件(2026-10-24 時点、事実のみ)

- 次の 4 つの組織は、App のインストールを待っています。それぞれの組織への App のインストールが済むまで、これらの repo は同期できません。
  - `project-fusha/platform`
  - `HAL-IAIH-team-F/k8s-hew`
  - `Code-Sakura/code-sakura-k8s`
  - `as-wasabi/k8s-wasabi`
- `OneServerMC/k8s` は、app path `develop` が存在しません(別件)。
- `charts.pingcap.org` は DNS が引けません(別件)。

---

## 6. 秘密鍵の保管

- 方針: 秘密鍵は Bitwarden に保管し、必要なら BitwardenSecret で `argocd` namespace に同期します。
- **現状: 未実施**(鍵は Bitwarden へ移していません。同期の仕組みも作っていません)。

---

## 関連

- ArgoCD の構成全体: [`CLAUDE.md`](../CLAUDE.md)
- Secret の扱い: `CLAUDE.md` の「Secret Management Pattern」
