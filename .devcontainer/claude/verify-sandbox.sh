#!/usr/bin/env bash
# サンドボックスの制限が効いていることを確かめる。
# devcontainer の postStartCommand で起動のたびに実行される。手動でも `verify-sandbox` で実行できる。
set -u

pass=0
fail=0
warn=0
T="timeout 8"

ok()   { echo "  ✔ $1"; pass=$((pass + 1)); }
ng()   { echo "  ✘ $1"; fail=$((fail + 1)); }
note() { echo "  ⚠ $1"; warn=$((warn + 1)); }

# 成功したら NG（＝外に出られてしまった）
expect_fail() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then ng "$desc"; else ok "$desc"; fi
}
expect_ok() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else ng "$desc"; fi
}
mount_opts() { awk -v p="$1" '$2 == p { o = $4 } END { print o }' /proc/mounts; }
is_ro() { mount_opts "$1" | grep -qE '(^|,)ro(,|$)'; }
can_write() {
  local f="$1/.verify-sandbox-$$"
  ( : > "$f" ) 2>/dev/null && rm -f "$f"
}

NOPROXY_ENV=(env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u NODE_USE_ENV_PROXY)

echo "[ネットワーク] すべて失敗すること"
expect_fail "許可していないドメインへの curl（プロキシ経由）" $T curl -sf -o /dev/null https://example.com
expect_fail "IP 直接指定の HTTPS（プロキシを無視）"          $T curl -sf -o /dev/null --noproxy '*' https://1.1.1.1
expect_fail "IP 直接指定の HTTP（プロキシを無視）"           $T curl -sf -o /dev/null --noproxy '*' http://1.1.1.1
expect_fail "dig @8.8.8.8 での名前解決"                       $T dig +time=3 +tries=1 @8.8.8.8 example.com
expect_fail "コンテナの DNS で外部ドメインを解決"             getent hosts example.com
expect_fail "IPv6 での通信"                                    $T curl -sf -o /dev/null -6 --noproxy '*' 'https://[2606:4700:4700::1111]'
expect_fail "プロキシ環境変数を外した curl"                   "${NOPROXY_ENV[@]}" $T curl -sf -o /dev/null https://example.com
expect_fail "プロキシ環境変数を外した Node.js fetch()"        "${NOPROXY_ENV[@]}" $T node -e \
  "fetch('https://1.1.1.1').then(() => process.exit(0), () => process.exit(1))"
expect_fail "デフォルトルートが存在する"                      grep -qE '^\S+\s+00000000\s' /proc/net/route

echo "[ネットワーク] 使えること"
expect_ok "api-gateway に到達できる" $T curl -sf -o /dev/null http://api-gateway:8080/healthz

echo "[権限]"
if [ "$(id -u)" != "0" ]; then ok "非 root ユーザー（$(id -un)）"; else ng "root で動いている"; fi
if command -v sudo >/dev/null 2>&1; then ng "sudo が入っている"; else ok "sudo がない"; fi
if grep -qE '^NoNewPrivs:\s*1' /proc/self/status; then ok "no-new-privileges"; else ng "no-new-privileges が無効"; fi
if grep -qE '^CapBnd:\s*0+$' /proc/self/status; then ok "capability がすべて落ちている"; else ng "capability が残っている（$(grep CapBnd /proc/self/status)）"; fi
if [ -e /var/run/docker.sock ] || [ -e /run/docker.sock ]; then ng "docker.sock がマウントされている"; else ok "docker.sock がない"; fi

echo "[ファイルシステム]"
if is_ro /; then ok "ルートファイルシステムが読み取り専用"; else ng "ルートファイルシステムが書き込み可"; fi
for p in /workspace/.git /workspace/.devcontainer /workspace/.claude; do
  if is_ro "$p"; then ok "$p が読み取り専用"; else ng "$p が書き込み可（ホスト側で実行され得る）"; fi
done
for p in /workspace /workspace/.claude/skills; do
  if can_write "$p"; then ok "$p に書き込める"; else ng "$p に書き込めない（ホスト側の所有者・UID を確認）"; fi
done

echo "[認証情報]"
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then ng "ANTHROPIC_API_KEY がコンテナ内にある"; else ok "ANTHROPIC_API_KEY はコンテナ内にない"; fi
case "${ANTHROPIC_AUTH_TOKEN:-}" in
  sk-ant-*) ng "ANTHROPIC_AUTH_TOKEN に本物のキーが入っている" ;;
  *)        ok "ANTHROPIC_AUTH_TOKEN はダミー（キーは api-gateway が注入）" ;;
esac
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK}" ]; then
  note "SSH エージェントが転送されている（$SSH_AUTH_SOCK）"
else
  ok "SSH エージェントは転送されていない"
fi
if helper=$(git config --get-all credential.helper 2>/dev/null) && [ -n "$helper" ]; then
  note "git の credential.helper が設定されている（$helper）"
else
  ok "git の credential.helper は未設定"
fi
if [ -e "$HOME/.git-credentials" ]; then note "~/.git-credentials がある"; else ok "~/.git-credentials がない"; fi

echo
echo "結果: OK ${pass} / NG ${fail} / 警告 ${warn}"
if [ "$fail" -gt 0 ]; then
  echo "サンドボックスの制限が効いていません。上の ✘ を確認してください。" >&2
  exit 1
fi
if [ "$warn" -gt 0 ]; then
  echo "⚠ はホスト側の VS Code 設定で止められます（README の「VS Code 側の設定」参照）。"
fi
