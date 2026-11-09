FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends squid squidclient \
 && rm -rf /var/lib/apt/lists/*

COPY squid.conf /etc/squid/squid.conf

# root で起動して権限を落とす方式は cap_drop: ALL と両立しないので、最初から proxy ユーザーで動かす
USER proxy
EXPOSE 3128
CMD ["squid", "-N", "-f", "/etc/squid/squid.conf"]
