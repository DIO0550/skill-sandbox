#!/usr/bin/env bash
# Claude Code 以外の AI コーディングツールの CLI をイメージに入れるスクリプト。
# Dockerfile から root で実行する。
#
# 元にしたもの: https://gist.github.com/DIO0550/148b1392cf435ba3562da0d398bee442 （install-ai-tools.sh）
# gist からの変更点:
#   - Claude Code は入れない（Dockerfile で npm から root 所有で入れている。ここでネイティブ版を
#     ~/.local/bin に入れると、sandbox のユーザーが書き換えられる claude が PATH の手前に来てしまう）
#   - 各ツールを /opt/ai-tools に root 所有で入れ、コマンドだけ /usr/local/bin にリンクする。
#     sandbox のユーザー（非 root）はバイナリを書き換えられない
#   - pnpm / safe-chain の前提チェックは省いた（どのインストーラーも npm / pnpm を使わないため）
#   - シェルの設定ファイル（.bashrc など）は書き換えない
#
# 実行時（コンテナ内）の通信先は proxy/allowed-domains.txt で許可する必要がある。
set -euo pipefail

PREFIX="${AI_TOOLS_PREFIX:-/opt/ai-tools}"
LINK_DIR="${AI_TOOLS_LINK_DIR:-/usr/local/bin}"
BIN="$PREFIX/bin"

log() { echo "[ai-tools] $*"; }

# インストーラーには使い捨ての HOME を渡す。シェルの設定ファイルやキャッシュをそこに書かせて、
# 終わったら消す。BIN と LINK_DIR を PATH に入れておくと、多くのインストーラーは
# 「PATH 設定済み」と判断して設定ファイルに追記しない。
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$BIN" "$LINK_DIR"
export PATH="$BIN:$LINK_DIR:$PATH"

# 公式インストーラーを取得して実行する: run_installer <名前> <URL> <インタプリタ> [引数...]
# 環境変数は呼び出し側で `env` を前置して渡す。
run_installer() {
  local name="$1" url="$2" interp="$3"
  shift 3
  local script="$scratch/$name-install.sh"
  local home="$scratch/home-$name"
  mkdir -p "$home"
  log "installing $name ($url)"
  curl -fsSL "$url" -o "$script"
  HOME="$home" "$interp" "$script" "$@" </dev/null
}

# GitHub Copilot CLI → $PREFIX/bin/copilot
PREFIX="$PREFIX" run_installer copilot https://gh.io/copilot-install bash

# OpenAI Codex CLI → $PREFIX/bin/codex（本体は $PREFIX/codex/packages 以下）
CODEX_INSTALL_DIR="$BIN" CODEX_HOME="$PREFIX/codex" CODEX_NON_INTERACTIVE=true \
  run_installer codex https://chatgpt.com/codex/install.sh sh

# Cursor CLI: インストール先が $HOME/.local/share/cursor-agent 固定なので、入れた後に移す
run_installer cursor https://cursor.com/install bash
rm -rf "$PREFIX/cursor"
cp -a "$scratch/home-cursor/.local/share/cursor-agent" "$PREFIX/cursor"
cursor_bin="$(find "$PREFIX/cursor/versions" -mindepth 2 -maxdepth 2 -name cursor-agent -type f | sort | tail -n 1)"
[ -n "$cursor_bin" ] || { echo "[ai-tools] cursor-agent binary not found" >&2; exit 1; }
ln -sfn "$cursor_bin" "$BIN/cursor-agent"
ln -sfn "$cursor_bin" "$BIN/agent"

# Antigravity CLI → $PREFIX/bin/agy
run_installer antigravity https://antigravity.google/cli/install.sh bash --dir "$BIN"

# OpenCode: インストール先が $HOME/.opencode/bin 固定なので、入れた後に移す
run_installer opencode https://opencode.ai/install bash --no-modify-path
install -m 0755 "$scratch/home-opencode/.opencode/bin/opencode" "$BIN/opencode"

# root 所有・読み取りと実行だけ許可にして、コマンドを LINK_DIR にリンクする
chown -R root:root "$PREFIX" 2>/dev/null || true
chmod -R go-w,a+rX "$PREFIX"
for cmd in copilot codex cursor-agent agent agy opencode; do
  if [ ! -e "$BIN/$cmd" ]; then
    echo "[ai-tools] $cmd was not installed" >&2
    exit 1
  fi
  ln -sfn "$BIN/$cmd" "$LINK_DIR/$cmd"
done

log "installed:"
for cmd in copilot codex cursor-agent agy opencode; do
  printf '  %-13s %s\n' "$cmd" "$(readlink -f "$LINK_DIR/$cmd")"
done
