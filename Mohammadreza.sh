#!/bin/bash

set -e

echo "======================================"
echo "        Server Installation Script"
echo "======================================"

echo ""
echo "===== Update System ====="

apt update
apt install -y certbot unzip curl

echo ""
echo "===== Install Docker ====="

curl -fsSL https://get.docker.com -o get-docker.sh
bash get-docker.sh

echo ""
echo "===== Configure GRE Tunnel ====="

# Automatically detect server local IP
LOCAL_IP=$(ip -4 route get 8.8.8.8 | awk '{print $7; exit}')

echo "Detected Local IP: $LOCAL_IP"

# Ask for Iran server public IP
read -p "Enter Iran Public IP (Remote): " REMOTE_IP

mkdir -p /etc/netplan

cat > /etc/netplan/gre.yaml << EOF
network:
  version: 2
  renderer: networkd

  ethernets:
    eth0:
      dhcp4: true

  tunnels:
    gre1:
      mode: gre
      local: $LOCAL_IP
      remote: $REMOTE_IP
      addresses:
        - 10.100.100.2/30
      mtu: 1400
EOF

echo "Applying netplan..."

netplan generate
netplan apply


# ==================================================
# SSL CERTIFICATE
# ==================================================

echo ""
echo "===== SSL Certificate Selection ====="

echo ""
echo "Select the domain:"
echo "1) Vanooshe"
echo "2) Hidden-Bits"
echo ""

read -p "Enter your choice (1 or 2): " DOMAIN_CHOICE

case "$DOMAIN_CHOICE" in

    1)
        DOMAIN="Vanooshe"
        SSL_URL="https://vanooshe.s3.ir-thr-at1.arvanstorage.ir/Vanooshe.zip"
        ;;

    2)
        DOMAIN="Hidden-Bits"
        SSL_URL="https://vanooshe.s3.ir-thr-at1.arvanstorage.ir/Hidden-Bits.zip"
        ;;

    *)
        echo "WARNING: Invalid selection."
        echo "Skipping SSL certificate installation..."
        DOMAIN=""
        SSL_URL=""
        ;;

esac


if [ -n "$SSL_URL" ]; then

    echo ""
    echo "Selected Domain: $DOMAIN"
    echo "Downloading SSL certificate..."

    SSL_FILE="/tmp/letsencrypt.zip"

    if curl -fL \
        --connect-timeout 15 \
        --max-time 60 \
        "$SSL_URL" \
        -o "$SSL_FILE"; then

        echo "SSL certificate download successful."

        rm -rf /etc/letsencrypt

        rm -rf /tmp/letsencrypt

        if unzip -o "$SSL_FILE" -d /tmp; then

            if [ -d "/tmp/letsencrypt" ]; then

                mv /tmp/letsencrypt /etc/

                chmod -R 755 /etc/letsencrypt

                echo ""
                echo "SSL certificates restored successfully."
                echo "Domain: $DOMAIN"

            else

                echo "WARNING: letsencrypt directory not found in ZIP."
                echo "Skipping SSL certificate installation..."

            fi

        else

            echo "WARNING: Failed to extract SSL certificate."
            echo "Skipping SSL certificate installation..."

        fi

    else

        echo "WARNING: Failed to download SSL certificate."
        echo "Skipping SSL certificate installation..."

    fi

    rm -f "$SSL_FILE"

fi


# ==================================================
# INSTALL 3X-UI
# ==================================================

echo ""
echo "===== Install 3X-UI ====="

mkdir -p /root/x-ui
cd /root/x-ui

cat > docker-compose.yml << 'EOF'
version: '3.9'

services:
  xui:
    image: ghcr.io/mhsanaei/3x-ui:v2.8.8
    container_name: x-ui
    volumes:
      - /root/x-ui/db/:/etc/x-ui/
      - /etc/letsencrypt/:/etc/letsencrypt/
    restart: unless-stopped
    network_mode: host
EOF

echo "Starting 3X-UI..."

if command -v docker-compose >/dev/null 2>&1; then
    docker-compose up -d
else
    docker compose up -d
fi


# ==================================================
# FINAL
# ==================================================

echo ""
echo "======================================"
echo "Installation completed successfully!"
echo "======================================"

echo "GRE Local IP  : $LOCAL_IP"
echo "GRE Remote IP : $REMOTE_IP"
echo "Tunnel IP     : 10.100.100.2/30"

if [ -n "$DOMAIN" ]; then
    echo "SSL Domain    : $DOMAIN"
else
    echo "SSL Domain    : Not installed"
fi

echo "3X-UI         : Started"

echo "======================================"
echo ""

echo "Installation completed."
echo "Rebooting in 10 seconds..."

sleep 10

reboot