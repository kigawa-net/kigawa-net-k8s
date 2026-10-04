# karmada-etcd

Karmada 専用の external etcd(Inuyama の etcd #1)。`karmada-etcd` namespace、VIP `10.0.0.243`。
将来 Soichiro / IONOS の member を足して 3 member(quorum 2/3)にする前提。

## 構成

- StatefulSet `karmada-etcd`(1 レプリカ、Guaranteed QoS)、PVC は `rook-ceph-rbd` 10Gi
- `karmada-etcd-lb`(LoadBalancer、`10.0.0.243`、`externalTrafficPolicy: Local`): client 2379 / peer 2380
- 証明書は Bitwarden(プロジェクト `infra`)から `BitwardenSecret` で同期。**Git には入っていない**
  - `karmada-etcd-ca-crt` / `karmada-etcd-ca-key`: etcd の CA(秘密鍵は**クラスタに渡さない**。member 追加時の証明書発行用)
  - `karmada-etcd-server-crt` / `-key`: etcd #1 のサーバー/ピア証明書(SAN: `10.0.0.243`、`127.0.0.1`、`localhost`、Pod の DNS)
  - `karmada-etcd-client-crt` / `-key`: Karmada API サーバーが etcd に接続するクライアント証明書
  - `karmada-apiserver-ca-crt` / `-key`: Operator の `customCertificate.apiServerCACert`(段階 2 で他拠点と共有する CA)
- 証明書の有効期限: CA 10 年、リーフ 5 年(2031-10-03)。更新前に、新しいリーフを同じ CA で発行して Bitwarden を更新する。

## ストレージの注意(重要)

既存の Karmada の etcd は Ceph RBD 上で、読み取りに 0.5〜5 秒かかり、リース更新に失敗して
コンポーネントが数百回再起動した(2026-10-04)。ストレージを Ceph RBD にする判断は維持しているが、
**Karmada CR を適用する前に、次を確認する**:

```
# etcd のメトリクス(Prometheus)
histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket{namespace="karmada-etcd"}[5m]))
histogram_quantile(0.99, rate(etcd_disk_backend_commit_duration_seconds_bucket{namespace="karmada-etcd"}[5m]))
```

- 基準: wal_fsync の p99 が **25ms 以下**、backend_commit の p99 が **100ms 以下**。
- 超える場合は、worker3(ベアメタル SSD、fsync 0.6ms を実測)のローカルディスクに切り替える
  (StatefulSet の `volumeClaimTemplates` を `hostPath`(`DirectoryOrCreate`)+ nodeAffinity に変更)。

## 3 member にするとき

- etcd の timer(`--heartbeat-interval=250` / `--election-timeout=3000`)は、Inuyama ↔ IONOS の RTT(約 157ms)に合わせてある。全 member で同じ値にする。
- 新しい member は `etcdctl member add` で足す(`--initial-cluster-state=existing`)。リーダーが遅いディスクの member
  (Inuyama の Ceph RBD)になった場合は、`etcdctl move-leader` で速い member に移す。
- 各 member の証明書は、`karmada-etcd-ca-key` で署名して、SAN に実際に advertise する IP を入れる。
