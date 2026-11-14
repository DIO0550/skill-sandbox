# syntax=docker/dockerfile:1
FROM node:22-bookworm-slim

ARG CLAUDE_CODE_VERSION=latest
ARG USERNAME=claude
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

# Tools Claude Code commonly shells out to while developing skills.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq less procps ripgrep unzip vim-tiny python3 \
 && rm -rf /var/lib/apt/lists/*

# Other AI coding CLIs (GitHub Copilot CLI, Codex, Cursor CLI, Antigravity, OpenCode),
# installed with the same gists as spec-viewer, unmodified and fetched at build time:
#   pnpm-safe-chain-setup.sh  pnpm + safe-chain (install-ai-tools.sh checks for them first)
#   install-ai-tools.sh       the AI CLIs (and a native Claude Code, which link-ai-tools.sh removes)
# They run as root with HOME=/opt/ai-tools so everything lands root-owned there, then
# link-ai-tools.sh links the commands into /usr/local/bin.
# Their API hosts are not allowed by default: see proxy/allowed-domains.txt.
ARG SAFE_CHAIN_GIST_URL=https://gist.githubusercontent.com/DIO0550/dcc09dc9d2dcefceb9b0cda183e7ef8e/raw/pnpm-safe-chain-setup.sh
ARG AI_TOOLS_GIST_URL=https://gist.githubusercontent.com/DIO0550/148b1392cf435ba3562da0d398bee442/raw/install-ai-tools.sh
RUN --mount=type=bind,source=ai-tools/link-ai-tools.sh,target=/tmp/link-ai-tools.sh \
    export HOME=/opt/ai-tools \
 && mkdir -p "$HOME" /tmp/gists \
 && curl -fsSL "$SAFE_CHAIN_GIST_URL" -o /tmp/gists/pnpm-safe-chain-setup.sh \
 && curl -fsSL "$AI_TOOLS_GIST_URL" -o /tmp/gists/install-ai-tools.sh \
 && sh /tmp/gists/pnpm-safe-chain-setup.sh \
 && bash /tmp/gists/install-ai-tools.sh </dev/null \
 && bash /tmp/link-ai-tools.sh \
 && rm -rf /tmp/gists /root/.npm

# Install Claude Code globally (as root, so the non-root user cannot modify it).
# This comes after the gists: the gist's native Claude Code installer removes an existing
# global npm install of Claude Code.
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && npm cache clean --force \
 && claude --version

# Reuse the base image's uid/gid 1000 "node" account, renamed and re-numbered
# to match the host user so bind-mounted files keep sane ownership.
# -o allows ids that already exist in the image (e.g. gid 20 on macOS, gid 100 "users").
RUN if [ "${USER_UID}" = "0" ]; then echo "USER_UID must not be 0: the sandbox user has to be non-root" >&2; exit 1; fi \
 && groupmod -o -n "${USERNAME}" -g "${USER_GID}" node \
 && usermod -o -l "${USERNAME}" -u "${USER_UID}" -g "${USER_GID}" \
      -d "/home/${USERNAME}" -m -s /bin/bash node \
 && mkdir -p "/home/${USERNAME}/.claude/skills" /workspace \
 && chown -R "${USER_UID}:${USER_GID}" "/home/${USERNAME}" /workspace

USER ${USERNAME}
WORKDIR /workspace

ENV HOME=/home/${USERNAME} \
    CLAUDE_CONFIG_DIR=/home/${USERNAME}/.claude \
    DISABLE_AUTOUPDATER=1 \
    SHELL=/bin/bash

CMD ["bash", "-l"]
