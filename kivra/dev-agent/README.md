# kivra-agent の k8s 実行基盤(dev)— ADR 0010 追補 7 の PR 5b

kivra の自己開発エージェントが、Run(attempt)ごとの k8s Job でコーディング CLI を動かすための manifest。
正本の設計は kigawa-net/kivra の `docs/adr/0010-...md` 追補 7 と `docs/runbook-selfdev.md` §6.6b・§6.6c。

## 現状: ArgoCD に拾われない(何も適用されない)

このディレクトリ(`kivra/dev-agent/`)を指す ArgoCD の Application は **まだ無い**。既存の `apps/kivra-dev-app.yml` は
`path: kivra/dev` を指し、`kivra/dev-agent` は含まない(兄弟ディレクトリ)。ルートの `apps/apps-app.yml` が再帰するのは `apps/` だけで、
この README の Application の雛形は `apps/` に置いていない。よって **マージしても、namespace・NetworkPolicy・RBAC・Deployment のどれも作られない**。
有効化は、下の手順 1 で Application を足す PR で行う(それが、これらが cluster に現れる瞬間)。

## 構成

| ファイル | namespace | 内容 |
|---|---|---|
| `ns.yaml` | (cluster) | Job 用の専用 namespace `kigawa-net-kivra-dev-agent`。PodSecurity `restricted` を enforce / audit / warn |
| `kivra-agent-netpol-default-deny.yaml` | job | 全 Pod の ingress・egress を全拒否 |
| `kivra-agent-netpol-job.yaml` | job | Job の Pod(`kivra-agent=1`)の egress はプロキシの 8080 と kube-dns の 53 だけ |
| `kivra-agent-netpol-proxy.yaml` | job | プロキシの ingress は Job の Pod の 8080 だけ。egress は DNS と、公開 IP の TCP 443 |
| `kivra-agent-proxy.yaml` | job | egress プロキシの Deployment(**replicas: 0**。非 root、read-only rootfs、drop ALL、seccomp、canal ノードに限定) |
| `kivra-agent-proxy-svc.yaml` / `-cm.yaml` / `-sa.yaml` | job | Service、非秘密の設定(WIF の ID は空)、ServiceAccount(権限なし) |
| `kivra-agent-proxy-bws.yaml` | job | Keycloak client secret(BitwardenSecret。**bws の ID はプレースホルダ**) |
| `kivra-agent-role.yaml` / `kivra-agent-rb.yaml` | job | agent の Role と RoleBinding(下記の最小権限) |
| `kivra-agent-sa.yaml` | kivra-dev | agent 本体の ServiceAccount |
| `kivra-agent.yaml` | kivra-dev | agent 本体の Deployment(**replicas: 0**、backend 未設定=docker、executor=stub) |
| `kivra-agent-bws.yaml` | kivra-dev | agent 本体の Keycloak client secret(BitwardenSecret。**bws の ID はプレースホルダ**) |

### 設計の選択

- **namespace を分ける**: kivra 本体の namespace では PodSecurity の enforce と default-deny を掛けられない。agent の RBAC も Job の namespace だけに閉じられる。
  `kivra-agent` の `K8sSettings.namespace` は `kigawa-net-kivra-dev-agent` にする(PR 5c)。AppProject は `kigawa-net-*` を許可しているので追加の許可は要らない。
- **agent 本体は本体の namespace(kigawa-net-kivra-dev)に置く**: kivra へは公開の ingress(`/api/agent/`)経由で届く。Job の namespace は default-deny なので、agent を置かない。
  RoleBinding が、本体の namespace の ServiceAccount に Job の namespace の Role を与える。
- **RBAC は KubeApi.kt の KDoc と同じ**: `batch/jobs` の create・get・list・delete、`pods` の get・list、`pods/log` の get、`pods/exec` の create・get。
  deletecollection、secrets、configmaps、ClusterRole は無し。
- **NetworkPolicy にできること・できないこと**: NetworkPolicy は IP とポートでしか絞れず、FQDN を指定できない。
  Job の Pod はプロキシ(Pod セレクタ)と DNS だけに絞れる。プロキシの外向きは「公開 IP の TCP 443」までで、
  どのホストに出てよいかは **プロキシの許可リスト(`allowlist.txt`、イメージに焼いてある)** と `rejectNonPublic` が担う。
  プロキシが侵害されても、クラスタ内・LAN・メタデータ・443 以外には届かない(これが NetworkPolicy の役割)。
- **NetworkPolicy が効くのは canal-cni=enabled のノードの Pod だけ**(prod の CNI の切替が途中。flannel の Pod と canal の Pod は相互に通信できない)。
  プロキシは `nodeAffinity`(`canal-cni In [enabled]`)で限定した。**Job の Pod は kivra-agent のコード(`K8sJobBuilder` の `nodeSelector: canal-cni=enabled` と、`K8sJobGuard` の許可)の変更が必要=PR 5c の作業**で、ここでは書けない。
  k8s1・k8s2 の切替が終われば、この制約は外せる。
- **Secret の値は git に無い**: Keycloak client secret は bws から BitwardenSecret で同期する(既存の `kivra-github-app-bws.yaml` と同じ形)。
- プロキシは Dockerfile では root で動かす前提だが、k8s では `runAsUser: 65532` + `fsGroup` + Secret の `defaultMode: 0440` で非 root にした(PodSecurity restricted のため)。
- 運用で固定する値: イメージのタグ(Harbor に push 済みか要確認。deploy-dev の自動更新は `kivra.yaml` だけが対象)、WIF の ID、Keycloak client ID。

## 有効化の手順(順番どおり。1〜5 は k8s バックエンドを有効にしない)

前提: prod の CNI の切替が終わっている(k8s1・k8s2 も canal)、または Job・プロキシが canal ノードにだけ載る(上記)。

1. **Application を足す PR**: `apps/kivra-dev-agent-app.yml` を作る。`kivra-dev-app.yml` と同じ形で `path: kivra/dev-agent`、`recurse: true`、
   `destination.namespace: kigawa-net-kivra-dev-agent`、`syncOptions: [CreateNamespace=true, ApplyOutOfSyncOnly=true]`。prune は有効でよい。
   このマージで namespace・NetworkPolicy・RBAC・ServiceAccount・ConfigMap・Service が作られ、Deployment は replicas 0 で作られる。
   BitwardenSecret は、bws の ID が 0 のままだと同期に失敗する(Secret ができないだけで、Pod は 0 なので影響はない)。
2. **Secret の準備(運用者)**: bws に client secret を作り、2 つの `*-bws.yaml` の `bwSecretId` を実際の ID にする(PR)。
   `kigawa-system/secret-provider/bitwarden-sync-crn.yaml` の `TARGET_NAMESPACES` に `kigawa-net-kivra-dev-agent` を足す(`bitwarden-sec` の配布)。
   Job の namespace に `harbor-registry`(イメージの pull 用)の Secret が必要(kivra-dev と同じ方法で用意する)。
3. **値の記入**: `kivra-agent-proxy-cm.yaml` の WIF の 4 つの ID(Anthropic Console の WIF 設定)、`kivra-agent.yaml` の `KIVRA_AGENT_CLIENT_ID`、イメージのタグ。
4. **default-deny の確認(プロキシも agent も 0 のまま)**: 下の検証 1・2 を、使い捨ての Pod で行う。
5. **プロキシを起動**: `kivra-agent-proxy.yaml` の `replicas: 0` を 1 にする PR。Pod が canal ノードで Ready になり、ログに設定エラーが無いこと。
6. **実クラスタでの検証**(下の一覧)を全て通す。
7. **PR 5c(別の PR)**: kivra-agent の `AgentConfig`・`RunBackendFactory` で k8s を有効にし、Job に `nodeSelector` とプロキシの env(`HTTPS_PROXY`、`ANTHROPIC_BASE_URL`)を渡す配線を入れる。
   `kivra-agent.yaml` に `KIVRA_AGENT_BACKEND=k8s` と K8s の設定(namespace、許可イメージ)を足し、replicas を 1 にする。ここで初めて k8s の既定が有効になる。

## 後日の検証チェックリスト(ADR 0010 追補 7 §3・§7)

使い捨ての検証用 Pod は、Job の Pod と同じ label(`kivra-agent=1`)・securityContext で `kigawa-net-kivra-dev-agent` に作る。
**1 件でも失敗したら、k8s の既定への切り替えを止める**(追補 7 §7)。

- [ ] Job の Pod から、プロキシ以外への到達が無い: 外部(`curl https://example.com` を直接)、他 namespace の Service、Pod の IP、`kubernetes.default`(API server)、メタデータ(169.254.169.254)、プロキシの 8080 以外のポートが、全て失敗する。
- [ ] Job の Pod から、プロキシ Service の 8080 と kube-dns の 53 だけは届く(`HTTPS_PROXY` 経由の CONNECT が、許可リストのホストには成功し、許可外のホストには 403)。
- [ ] ingress が全拒否: 他の Pod から Job の Pod に届かない。プロキシには Job の Pod からしか届かない(別の label の Pod からは届かない)。
- [ ] プロキシから、許可リストのホストの 443 に届く。クラスタ内の IP・RFC 1918・443 以外には届かない(NetworkPolicy と `rejectNonPublic` の両方)。
- [ ] プロキシが Keycloak と Anthropic の WIF の交換に成功する(`/anthropic` を経由した最小の呼び出し)。Secret の値がログに出ない。
- [ ] exec の readout: agent が `pods/exec`(WebSocket)で `/work/.kivra/result.json` を読め、入力を stdin で送れる。API server → kubelet の経路は NetworkPolicy の影響を受けない。
- [ ] RBAC が最小: `kubectl auth can-i --as=system:serviceaccount:kigawa-net-kivra-dev:kivra-agent` で、Job の namespace の jobs の create/get/list/delete、pods の get/list、pods/log の get、pods/exec の create/get だけが yes。
  deletecollection、secrets、configmaps、pods の create/delete、他の namespace、cluster 全体は no。
- [ ] PodSecurity: restricted に違反する Pod(privileged、hostPath、root)は admission で拒否される。Job の Pod とプロキシは、warn なしで作られる。
- [ ] Job の Pod が canal ノードにだけ載る(nodeSelector の配線後)。Job の Pod とプロキシが別の CNI のノードにならない。
- [ ] `podPidsLimit`(kubelet の設定)が十分に小さい(pids は Pod 単位で指定できない。追補 7 §4 の運用確認)。
- [ ] 停止・時間切れ・孤児の掃除(label `kivra-agent=1`)で、Job が残らない。

## まだ行っていないこと

- ArgoCD の Application(手順 1)。cluster には何も作られていない。
- bws のシークレット、`bwSecretId`、`TARGET_NAMESPACES` への追加、`harbor-registry` の配布、WIF の ID、Keycloak client ID。
- イメージのタグが Harbor にあることの確認。
- Job の Pod の `nodeSelector` / プロキシ env の配線、`KIVRA_AGENT_BACKEND=k8s` の有効化(コード側が拒否したまま。PR 5c)。
- 上の検証の全て。NetworkPolicy の強制は、使い捨ての Pod での実測が済むまで確かめていない。
- 未決: agent とプロキシで Keycloak の client を分けるか(追補 7 §6)。分けるなら `kivra-agent-bws.yaml` の別 client にする。
