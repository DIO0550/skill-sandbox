#!/bin/bash
# allowed-domains.txt / squid.conf の変更を、動作中のプロキシに反映する。
#   docker compose exec proxy reload
# 先に設定を検査し、誤りがあるときは何も変更しない（動作中のプロキシは元の設定のまま動き続ける）。
set -uo pipefail
CONF=/etc/squid/sandbox/squid.conf

if ! out=$(squid -f "$CONF" -k parse 2>&1); then
  echo "設定に誤りがあるため反映しませんでした:" >&2
  echo "$out" | grep -iE "error|fatal|bungled|unrecognized" >&2
  exit 1
fi

squid -f "$CONF" -k reconfigure 2>/dev/null || { echo "プロキシに再読み込みを指示できませんでした" >&2; exit 1; }
echo "設定を反映しました。現在の許可ドメイン:"
grep -vE '^\s*(#|$)' /etc/squid/sandbox/allowed-domains.txt | sed 's/^/  /'
