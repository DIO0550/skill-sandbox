#!/bin/sh
# API キーを注入するリバースプロキシを起動する。
# キーはこのコンテナの環境変数にだけ存在し、claude コンテナからは見えない。
set -eu

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "api-gateway: ANTHROPIC_API_KEY が設定されていません（gateway.env を確認してください）" >&2
  exit 1
fi

export ANTHROPIC_UPSTREAM="${ANTHROPIC_UPSTREAM:-https://api.anthropic.com}"

envsubst '${ANTHROPIC_API_KEY} ${ANTHROPIC_UPSTREAM}' \
  < /etc/nginx/nginx.conf.template > /tmp/nginx.conf
chmod 0600 /tmp/nginx.conf

exec nginx -c /tmp/nginx.conf -g 'daemon off;'
