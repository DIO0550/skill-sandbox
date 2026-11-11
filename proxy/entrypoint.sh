#!/bin/bash
set -euo pipefail

CONF=/etc/squid/sandbox/squid.conf
CERT=/tmp/squid-bump.pem

# SNI を検査する設定（ssl-bump）には、ポート定義に証明書の指定が必須。
# 許可した通信は復号せずそのまま中継するので、起動のたびに作る使い捨ての自己署名証明書で足りる。
# この証明書がクライアントに見えるのは、許可していないドメインへの接続を拒否するときだけ
# （Squid は拒否の応答を TLS の中で返すため）。原因が分かるような名前を付けておく。
if [ ! -s "$CERT" ]; then
  umask 077
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/O=domain is not listed in proxy allowed-domains.txt/CN=blocked-by-skill-sandbox-proxy" \
    -keyout "$CERT" -out "$CERT.crt" 2>/dev/null
  cat "$CERT.crt" >> "$CERT"
  rm -f "$CERT.crt"
fi

squid -f "$CONF" -k parse >/dev/null 2>&1 || {
  echo "[proxy] ERROR: squid.conf または allowed-domains.txt に誤りがあります" >&2
  squid -f "$CONF" -k parse 2>&1 | grep -iE "error|fatal|bungled" >&2 || true
  exit 1
}

exec squid -f "$CONF" -N
