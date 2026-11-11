# sandbox コンテナのネットワーク名前空間を持ち、iptables でファイアウォールを張るだけのコンテナ。
# sandbox は `network_mode: service:firewall` でこの名前空間に相乗りするため、
# sandbox 自身に NET_ADMIN 権限を与えずにファイアウォールを適用できる。
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends iptables iproute2 \
 && rm -rf /var/lib/apt/lists/*

COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod 0755 /usr/local/bin/init-firewall.sh

CMD ["/usr/local/bin/init-firewall.sh"]
