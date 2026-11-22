#!/usr/bin/env bash
# Instalador del VPS (Ubuntu 24.04). Uso: sudo bash infra/install.sh
set -euo pipefail

apt-get update
apt-get install -y ca-certificates curl git ufw nginx certbot python3-certbot-dns-cloudflare

# Docker oficial
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

# Firewall: solo SSH y HTTPS
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Nginx
cp "$(dirname "$0")/nginx/dichoyhecho.conf" /etc/nginx/sites-available/dichoyhecho.conf
ln -sf /etc/nginx/sites-available/dichoyhecho.conf /etc/nginx/sites-enabled/dichoyhecho.conf

cat <<'MSG'
Listo. Pasos manuales:
1. Crear /root/.secrets/cloudflare.ini con el token de DNS (chmod 600) y correr:
   certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini -d api.dichoyhecho.ar
2. nginx -t && systemctl reload nginx
3. cp .env.example .env y completar valores
4. docker compose -f infra/docker-compose.yml run --rm migrate
5. docker compose -f infra/docker-compose.yml up -d --build worker
MSG
