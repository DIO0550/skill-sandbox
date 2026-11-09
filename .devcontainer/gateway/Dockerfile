FROM nginx:1.29-alpine

COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# 設定ファイルの生成・一時ファイルはすべて /tmp（tmpfs）に置き、非 root で動かす
USER nginx
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
