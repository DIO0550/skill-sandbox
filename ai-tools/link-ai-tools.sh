#!/usr/bin/env bash
# gist（install-ai-tools.sh）で /opt/ai-tools に入れた AI ツールの後始末をする。
# Dockerfile から root で実行する。gist 自体は編集せずにそのまま使う。
#
#   - gist は Claude Code のネイティブ版も入れるが、このイメージでは npm 版（/usr/local/bin/claude）を
#     使うので消す
#   - 残りのコマンドを /usr/local/bin にリンクする
#   - /opt/ai-tools を root 所有・読み取りと実行だけ許可にする（sandbox のユーザーは書き換えられない）
set -euo pipefail

AI_HOME="${AI_TOOLS_HOME:-/opt/ai-tools}"
LINK_DIR="${AI_TOOLS_LINK_DIR:-/usr/local/bin}"
COMMANDS=(copilot codex cursor-agent agent agy opencode)

# ネイティブ版の Claude Code と、インストール時に作られた設定・キャッシュを消す
rm -f "$AI_HOME/.local/bin/claude"
rm -rf "$AI_HOME/.local/share/claude" "$AI_HOME/.claude" "$AI_HOME"/.claude.json* \
       "$AI_HOME/.cache" "$AI_HOME/.npm"

# 各インストーラーの置き場所（~/.local/bin、~/.opencode/bin など）からコマンドを探してリンクする
search="$AI_HOME/.local/bin:$AI_HOME/.opencode/bin:$AI_HOME/bin:$LINK_DIR"
for cmd in "${COMMANDS[@]}"; do
  path="$(PATH="$search" command -v "$cmd" || true)"
  if [ -z "$path" ]; then
    echo "[ai-tools] $cmd was not installed by the gist" >&2
    exit 1
  fi
  if [ "$path" != "$LINK_DIR/$cmd" ]; then
    ln -sfn "$path" "$LINK_DIR/$cmd"
  fi
done

# claude が npm 版のままか確認する（npm 版の実体は @anthropic-ai/claude-code か、
# プラットフォーム別の @anthropic-ai/claude-code-linux-x64 などに置かれる）
claude_target="$(readlink -f "$LINK_DIR/claude")"
case "$claude_target" in
  */node_modules/@anthropic-ai/claude-code*) ;;
  *) echo "[ai-tools] $LINK_DIR/claude is not the npm-installed Claude Code: $claude_target" >&2; exit 1 ;;
esac

chown -R root:root "$AI_HOME"
chmod -R go-w,a+rX "$AI_HOME"
for cmd in "${COMMANDS[@]}"; do
  target="$(readlink -f "$LINK_DIR/$cmd")"
  chown root:root "$target"
  chmod go-w,a+rx "$target"
  printf '[ai-tools] %-13s %s\n' "$cmd" "$target"
done
