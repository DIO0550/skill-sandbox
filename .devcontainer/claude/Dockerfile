FROM node:24-bookworm-slim

# スキルのスクリプト実行・パッケージングに使う最低限のツール。sudo は入れない
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq less procps ripgrep \
      python3 python3-pip python3-venv \
      zip unzip dnsutils \
 && rm -rf /var/lib/apt/lists/*

ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && npm cache clean --force

# ユーザー設定では上書きできない managed settings
COPY managed-settings.json /etc/claude-code/managed-settings.json
COPY verify-sandbox.sh /usr/local/bin/verify-sandbox
RUN chmod 0644 /etc/claude-code/managed-settings.json \
 && chmod 0755 /usr/local/bin/verify-sandbox \
 && mkdir -p /workspace /home/node/.claude \
 && chown node:node /workspace /home/node/.claude

USER node
WORKDIR /workspace
