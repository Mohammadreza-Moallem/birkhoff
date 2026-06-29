#!/bin/bash

set -e

echo "===== Update System ====="
apt update
apt install -y certbot

echo ""
echo "===== Install Docker ====="
curl -fsSL https://get.docker.com -o get-docker.sh
bash get-docker.sh

echo ""
echo "===== Configure GRE Tunnel ====="

# Automatically detect server public/local IP
LOCAL_IP=$(ip -4 route get 8.8.8.8 | awk '{print $7; exit}')
echo "Detected Local IP: $LOCAL_IP"

# Ask only for Iran server public IP
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

if command -v docker-compose >/dev/null 2>&1; then
    docker-compose up -d
else
    docker compose up -d
fi

echo ""
echo "======================================"
echo "Installation completed successfully!"
echo "GRE Local IP  : $LOCAL_IP"
echo "GRE Remote IP : $REMOTE_IP"
echo "Tunnel IP     : 10.100.100.2/30"
echo "3X-UI started."
echo "======================================"
echo ""
echo "Installation completed. Rebooting in 10 seconds..."
sleep 10
reboot
