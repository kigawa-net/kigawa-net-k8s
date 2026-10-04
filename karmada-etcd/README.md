# karmada-etcd

Karmada 専用の external etcd(Inuyama の etcd #1)。`karmada-etcd` namespace、VIP `10.0.0.243`。
将来 Soichiro / IONOS の member を足して 3 member(quorum 2/3)にする前提。

## 構成

- StatefulSet `karmada-etcd`(1 レプリカ、Guaranteed QoS)、データは worker3 のローカルディスク(hostPath)
- `karmada-etcd-lb`(LoadBalancer、`10.0.0.243`、`externalTrafficPolicy: Local`): client 2379 / peer 2380
- 証明書は Bitwarden(プロジェクト `infra`)から `BitwardenSecret` で同期。**Git には入っていない**
  - `karmada-etcd-ca-crt` / `karmada-etcd-ca-key`: etcd の CA(秘密鍵は**クラスタに渡さない**。member 追加時の証明書発行用)
  - `karmada-etcd-server-crt` / `-key`: etcd #1 のサーバー/ピア証明書(SAN: `10.0.0.243`、`127.0.0.1`、`localhost`、Pod の DNS)
  - `karmada-etcd-client-crt` / `-key`: Karmada API サーバーが etcd に接続するクライアント証明書
  - `karmada-apiserver-ca-crt` / `-key`: Operator の `customCertificate.apiServerCACert`(段階 2 で他拠点と共有する CA)
- 証明書の有効期限: CA 10 年、リーフ 5 年(2031-10-03)。更新前に、新しいリーフを同じ CA で発行して Bitwarden を更新する。

## ストレージ(重要): worker3 のローカルディスク

etcd のデータは、**worker3(ベアメタル SSD)の `/var/lib/karmada-etcd`**(hostPath)に置く。

当初は Ceph RBD(`rook-ceph-rbd`)だったが、実際の PVC で `etcdctl check perf --load=s` を実行したところ、
基準を大きく超えて **FAIL** した(2026-10-04):

| 指標 | 基準 | Ceph RBD(実測) |
|---|---|---|
| 書き込みスループット | 150 writes/s 以上 | **11 writes/s**(リクエストのタイムアウトあり) |
| 最も遅いリクエスト | 約 1 秒以内 | **8.1 秒** |
| `wal_fsync` の p50 / p99 | p99 25ms 以下 | p50 約 0.5 秒 / p99 約 8 秒 |
| `backend_commit` の p50 / p99 | p99 100ms 以下 | p50 約 4 秒 / p99 約 8 秒 |

(既存の Karmada の etcd も、Ceph RBD 上で読み取りに 0.5〜5 秒かかり、リース更新に失敗して数百回再起動していた。)
worker3 のローカルディスクは、`dd oflag=dsync` で 0.6ms/回を実測している(worker4 は 75ms、worker1 は 289ms)。

- etcd は worker3 に固定される(nodeAffinity)。worker3 が落ちると etcd #1 も止まる。3 member 化で冗長化する。
- データはノードのローカルにあるので、worker3 を作り直す場合は、事前に `etcdctl snapshot save` を取る。
- 切り替え後は、同じコマンドで確認する:
  ```
  kubectl -n karmada-etcd exec karmada-etcd-0 -- etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/etcd/pki/ca.crt --cert=/etc/etcd/pki/tls.crt --key=/etc/etcd/pki/tls.key check perf --load=s
  ```
  メトリクス: `histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket{namespace="karmada-etcd"}[5m]))`
  (基準: wal_fsync の p99 が 25ms 以下、backend_commit の p99 が 100ms 以下)

## 3 member にするとき

- etcd の timer(`--heartbeat-interval=500` / `--election-timeout=5000`)は、全 member で同じ値にする。
  - 通常の経路: Inuyama ↔ Soichiro は Oracle 経由(実測 平均 約 12ms)。Inuyama ↔ IONOS は約 157ms。
  - 予備の経路(Oracle が止まったとき): Inuyama ↔ Soichiro は IONOS 経由で、実測 平均 354ms、最大 1078ms(Soichiro 担当者の計測、2026-10-04)。
  - 予備の経路でも、最大の揺れ(約 1.1 秒)に対して election が約 4.6 倍の余裕を持つように、500 / 5000 にした(以前は 250 / 3000 で、余裕は約 2.8 倍)。
  - 代償: リーダーが落ちたときの検知が、3 秒から 5 秒に伸びる。通常の書き込み遅延には影響しない。
- 新しい member は `etcdctl member add` で足す(`--initial-cluster-state=existing`)。リーダーが遅いディスクの member
  (Inuyama の Ceph RBD)になった場合は、`etcdctl move-leader` で速い member に移す。
- 各 member の証明書は、`karmada-etcd-ca-key` で署名して、SAN に実際に advertise する IP を入れる。

## バックアップと復元

- **定期バックアップ**: `backup-cronjob.yaml`(毎日 03:00 JST)。`etcdctl snapshot save` → `etcdutl snapshot status` で検証 → PVC `karmada-etcd-backup`(Ceph RBD)に `etcd-<日時>.db` で保存し、直近 14 世代を残す。
- **限界**: 保存先の PVC は、同じクラスタの Ceph の中にある。クラスタ全体の障害には備えられない。別の場所(オブジェクトストレージなど)へのコピーは、認証情報が要るため、別途対応する(未実施)。
- **手動で今すぐ取る**: `kubectl -n karmada-etcd create job --from=cronjob/karmada-etcd-backup backup-manual-$(date +%s)`
- **結果の確認**: `kubectl -n karmada-etcd logs job/<job名> -c store`(`etcdutl snapshot status` の結果は `-c verify`)
- **世代の一覧**: PVC `karmada-etcd-backup` をマウントした Pod で `ls -la /backup` を見る。
- **復元(Karmada の停止を伴う。実施前に必ず確認する)**:
  1. Karmada の apiserver などを止める(Operator の CR を一時的に外す、または Deployment を 0 にする)。
  2. etcd を止める(StatefulSet を 0 に)。
  3. `etcdutl snapshot restore <スナップショット> --data-dir <新しいディレクトリ> --name inuyama --initial-cluster inuyama=https://10.0.0.243:2380 --initial-advertise-peer-urls https://10.0.0.243:2380 --initial-cluster-token karmada-etcd-prod` で、worker3 の `/var/lib/karmada-etcd` に復元する(古いデータは、先に退避する)。
  4. etcd を起動して `endpoint health` を確認し、Karmada を戻す。
  - 3 member 化した後は、手順が変わる(全 member を止めて、1 つに復元してから、残りを足し直す)。

## peer の SAN の照合(--peer-skip-client-san-verification)

- etcd は、peer 接続のクライアント証明書の SAN を、**接続元の IP と照合**する。3 拠点の peer 通信は、NAT・flannel の SNAT を通り、接続元が証明書の SAN と一致しない(実測: Soichiro → Inuyama は k8s4 の flannel の `172.16.8.0`、Inuyama → Soichiro は worker3 の `192.168.1.130`)ため、`--peer-skip-client-san-verification=true` で、この照合を外している。**全メンバーで同じ設定にする。**
- **CA の署名の検証は、残る。** 接続できるのは、`karmada-etcd-ca` が署名した証明書を持つ相手のみ。CA の秘密鍵は Bitwarden(`karmada-etcd-ca-key`)に隔離している。
- 逆方向(Inuyama → Soichiro)は、このフラグに加えて、戻りの経路が要る(infra の k8s4 での MASQUERADE。infra #225)。
- 根本対応(送信元を証明書の SAN に合わせて、このフラグを外す)は、issue #272 の案 B。
