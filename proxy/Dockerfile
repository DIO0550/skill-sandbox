# 許可リスト型フォワードプロキシ（Squid）。
# TLS の SNI（接続先サーバー名）を検査するために、OpenSSL 版の Squid（squid-openssl）を使う。
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends squid-openssl openssl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY reload.sh /usr/local/bin/reload
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/reload

# root 権限は不要なので、最初から一般ユーザー（proxy）で動かす
USER proxy

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
