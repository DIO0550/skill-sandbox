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

# Install Claude Code globally (as root, so the non-root user cannot modify it).
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && npm cache clean --force

# Reuse the base image's uid/gid 1000 "node" account, renamed and re-numbered
# to match the host user so bind-mounted files keep sane ownership.
RUN groupmod -n "${USERNAME}" -g "${USER_GID}" node \
 && usermod -l "${USERNAME}" -u "${USER_UID}" -g "${USER_GID}" \
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
