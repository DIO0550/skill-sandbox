#!/bin/bash
# sandbox 用ファイアウォール
#
# 許可する通信:
#   - ループバック（Docker 内蔵 DNS 127.0.0.11 を含む）
#   - 確立済み接続の戻り
#   - プロキシコンテナの IP アドレス・ポート（既定 3128）への TCP 接続
# それ以外の送受信（ホストや他コンテナ、他ポート、UDP、ICMP、IPv6 など）はすべて拒否する。
set -euo pipefail

PROXY_HOST="${PROXY_HOST:-proxy}"
PROXY_PORT="${PROXY_PORT:-3128}"
READY_FILE=/run/firewall-ready

log() { echo "[firewall] $*"; }

rm -f "$READY_FILE"

# nftables が使えないカーネルでは legacy 版にフォールバックする
IPT=iptables
IP6T=ip6tables
if ! iptables -S >/dev/null 2>&1; then
  log "iptables (nft) unavailable, falling back to iptables-legacy"
  IPT=iptables-legacy
  IP6T=ip6tables-legacy
fi

# --- IPv4: まず全部閉じる ---
# filter テーブルだけを作り直す（nat テーブルには Docker 内蔵 DNS のルールがあるので触らない）
$IPT -F
$IPT -X
$IPT -P INPUT DROP
$IPT -P FORWARD DROP
$IPT -P OUTPUT DROP

$IPT -A INPUT  -i lo -j ACCEPT
$IPT -A OUTPUT -o lo -j ACCEPT
$IPT -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
$IPT -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# --- IPv6: ループバック以外すべて拒否 ---
if $IP6T -S >/dev/null 2>&1; then
  $IP6T -F
  $IP6T -X
  $IP6T -P INPUT DROP
  $IP6T -P FORWARD DROP
  $IP6T -P OUTPUT DROP
  $IP6T -A INPUT  -i lo -j ACCEPT
  $IP6T -A OUTPUT -o lo -j ACCEPT
  $IP6T -A OUTPUT -j REJECT
else
  log "ip6tables unavailable; skipping IPv6 rules"
fi

# --- プロキシの IP アドレスを調べる ---
# 許可先をサブネット全体にすると、ホスト（ブリッジのゲートウェイ）や他コンテナの
# 同じポートにも届いてしまう。プロキシコンテナの IP アドレス 1 つだけを許可する。
PROXY_IP=""
for _ in $(seq 1 30); do
  PROXY_IP=$(getent ahostsv4 "$PROXY_HOST" | awk 'NR==1 {print $1}') || true
  [ -n "$PROXY_IP" ] && break
  sleep 1
done
if [ -z "$PROXY_IP" ]; then
  log "ERROR: could not resolve the proxy host '${PROXY_HOST}'"
  exit 1
fi

log "allow tcp -> ${PROXY_IP}:${PROXY_PORT} (${PROXY_HOST})"
$IPT -A OUTPUT -p tcp -d "$PROXY_IP" --dport "$PROXY_PORT" -m conntrack --ctstate NEW -j ACCEPT

# 拒否はすぐ失敗が分かるよう REJECT にする
$IPT -A OUTPUT -p tcp -j REJECT --reject-with tcp-reset
$IPT -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited
$IPT -A INPUT  -j DROP

# --- 動作確認 ---
if ! timeout 5 bash -c "exec 3<>/dev/tcp/${PROXY_IP}/${PROXY_PORT}"; then
  log "ERROR: cannot reach ${PROXY_IP}:${PROXY_PORT} after applying rules"
  exit 1
fi
log "verified: proxy is reachable"

if ! $IPT -S OUTPUT | grep -qx -- '-P OUTPUT DROP'; then
  log "ERROR: OUTPUT policy is not DROP; firewall is not effective"
  exit 1
fi
log "verified: default OUTPUT policy is DROP"

touch "$READY_FILE"
log "firewall ready"

# sandbox がこのネットワーク名前空間を使い続けるので、終了せずに待機する
exec sleep infinity
