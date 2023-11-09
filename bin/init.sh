#!/usr/bin/env bash
echo "script_args: $@"
script_args="$@"

SSL_CERTIFICATE=/etc/nginx/ssl/certs/server-cert.pem
SSL_CERTIFICATE_KEY=/etc/nginx/ssl/private/server-key.pem

SERVER_NAME=_

if [ -n "$NGINX_SSL_CERT" ]; then
    SSL_CERTIFICATE=$NGINX_SSL_CERT
fi

if [ -n "$NGINX_SSL_CERT_KEY" ]; then
    SSL_CERTIFICATE_KEY=$NGINX_SSL_CERT_KEY
fi

if [ "$MONITORING_ENABLED" = "1" ]; then
    STUB_STATUS_LOCATION="
    # http only
    location /system-status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        allow 172.16.0.0/12;
        deny all;
    }"

    MONITORING_LOCATION="
    location /system-monitor {
        set \$grafana \"grafana\";
        proxy_pass http://\$grafana:3000;
        rewrite ^/system-monitor/?(.*) /\$1 break;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }"
fi

if [ "$LANDING_ENABLED" = "1" ]; then
    PRODUCTION_LOCATIONS="
    location /privacy-policy {
        root /etc/nginx/html/;
        index  index.html index.htm;

        expires -1;
        add_header Cache-Control no-store;

        try_files \$uri \$uri/ /index.html;
    }

    location /terms-of-use {
        root /etc/nginx/html/;
        index  index.html index.htm;

        expires -1;
        add_header Cache-Control no-store;

        try_files \$uri \$uri/ /index.html;
    }

    location ~* ^/info(?<route>.*) {
        set \$landing \"access-control-landing-page\";
        proxy_pass http://\$landing:3000\$route;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
    }
"
fi

if [ -n "$TELEGRAM_BOT_SECRET_PATH" ]; then
    TELEGRAM_BOT_LOCATION="
    location /$TELEGRAM_BOT_SECRET_PATH {
        set \$telegram_bot_host \"telegram-bot\";
        set \$telegram_bot_port \"8080\";

        proxy_pass http://\$telegram_bot_host:\$telegram_bot_port;
    }"
fi

if [ -n "$REDIRECT_FROM_IP" ] && [ -n "$REDIRECT_TO_HOSTNAME" ]; then
    SERVER_NAME=$REDIRECT_TO_HOSTNAME

    REDIRECT_FROM_IP_TO_HOSTNAME="
server {
    listen 80;
    listen 443 ssl;

    ssl_certificate $SSL_CERTIFICATE;
    ssl_certificate_key $SSL_CERTIFICATE_KEY;

    server_name $REDIRECT_FROM_IP;

    location / {
        return 301 https://$REDIRECT_TO_HOSTNAME\$request_uri;
    }
}"
fi

LISTENING_PORT_80="
    listen 80 default_server;
    listen [::]:80 default_server;"

LISTENING_PORT_443="
    listen 443 ssl;
    listen [::]:443 ssl;"

CERTIFICATE_SERVING_LOCATION="
    location /certs/ca {
        add_header Content-Type text/plain;
        alias ${SSL_CERTIFICATE};
        expires -1;
    }"

REDIRECT_SERVER="server {
    ${LISTENING_PORT_80}

    ${CERTIFICATE_SERVING_LOCATION}

    location / {
        return 301 https://\$host\$request_uri;
    }

    ${STUB_STATUS_LOCATION}
}
"

ACME_CERTBOT_SERVER="server {
    ${LISTENING_PORT_80}

    ${CERTIFICATE_SERVING_LOCATION}

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }

    ${STUB_STATUS_LOCATION}
}
"

declare -A MODES=(
    ["certbot"]="ACME_CERTBOT_SERVER='${ACME_CERTBOT_SERVER}'\
    LISTENING_PORT_443='${LISTENING_PORT_443}'"
    ["redirect"]="REDIRECT_SERVER='${REDIRECT_SERVER}'\
    LISTENING_PORT_443='${LISTENING_PORT_443}'"
    ["http_only"]="LISTENING_PORT_80='${LISTENING_PORT_80}'\
    STUB_STATUS_LOCATION='${STUB_STATUS_LOCATION}'"
    ["default"]="LISTENING_PORT_80='${LISTENING_PORT_80}'\
    LISTENING_PORT_443='${LISTENING_PORT_443}'\
    STUB_STATUS_LOCATION='${STUB_STATUS_LOCATION}'"
)

create_config() {
    echo "Starting nginx in '$current_mode' mode..."
    echo "Creation config from template..."
    eval  "${MODES[$current_mode]} \
    MONITORING_LOCATION='${MONITORING_LOCATION}' \
    PRODUCTION_LOCATIONS='${PRODUCTION_LOCATIONS}' \
    SSL_CERTIFICATE='$SSL_CERTIFICATE' \
    SSL_CERTIFICATE_KEY='$SSL_CERTIFICATE_KEY' \
    TELEGRAM_BOT_LOCATION='$TELEGRAM_BOT_LOCATION' \
    REDIRECT_FROM_IP_TO_HOSTNAME='$REDIRECT_FROM_IP_TO_HOSTNAME' \
    SERVER_NAME='$SERVER_NAME' \
    mo /templates/custom.conf.template > /etc/nginx/conf.d/custom.conf"
    cat /etc/nginx/conf.d/custom.conf
    echo "Genearated config:"
    echo "Starting nginx with command: $script_args"
    env /bin/sh -c "$script_args"
    # TODO: maybe move start commands inside?
    # ./bin/start_with_reloading.sh
}

case "$MODE" in
    certbot)
        current_mode=$MODE
        create_config
    ;;
    redirect)
        current_mode=$MODE
        create_config
    ;;
    http_only)
        current_mode=$MODE
        create_config
    ;;
    *)
        current_mode=default
        create_config
    ;;
esac
