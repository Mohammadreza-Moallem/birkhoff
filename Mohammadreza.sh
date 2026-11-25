
#!/bin/bash

set -e

echo "======================================"
echo "        Server Installation Script"
echo "======================================"

# ==================================================
# UPDATE SYSTEM
# ==================================================

echo ""
echo "===== Update System ====="

apt update
apt install -y curl python3 util-linux iputils-ping

# ==================================================
# INSTALL DOCKER
# ==================================================

echo ""
echo "===== Install Docker ====="

curl -fsSL https://get.docker.com -o get-docker.sh
bash get-docker.sh


# ==================================================
# CONFIGURE GRE TUNNEL
# ==================================================

echo ""
echo "===== Configure GRE Tunnel ====="

# Automatically detect server local IP
LOCAL_IP=$(ip -4 route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')

if [[ -z "$LOCAL_IP" ]]; then
    echo "ERROR: Unable to detect local IP"
    exit 1
fi

echo "Detected Local IP: $LOCAL_IP"

# Ask for Iran server public IP
read -p "Enter Iran Public IP (Remote): " REMOTE_IP

# Validate remote IPv4 address
python3 - "$REMOTE_IP" <<'PY'
import ipaddress
import sys

ip = ipaddress.IPv4Address(sys.argv[1])

if not ip.is_global:
    sys.exit("ERROR: Invalid public IPv4 address")
PY

mkdir -p /etc/netplan

# Backup existing GRE configuration
if [[ -f /etc/netplan/gre.yaml ]]; then
    cp -p /etc/netplan/gre.yaml \
        "/etc/netplan/gre.yaml.bak.$(date +%Y%m%d%H%M%S)"
fi

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

chmod 600 /etc/netplan/gre.yaml

echo "Applying netplan..."

netplan generate
netplan --debug apply


# ==================================================
# INSTALL GRE AUTO UPDATE SCRIPT
# ==================================================

echo ""
echo "===== Install GRE Auto Update Script ====="

mkdir -p /usr/local/sbin

cat > /usr/local/sbin/update-gre.sh <<'GREUPDATE'
#!/bin/bash

set -euo pipefail

CONFIG="/etc/netplan/gre.yaml"
BACKUP="/etc/netplan/gre.yaml.bak"

GRE_INTERFACE="gre1"
GRE_PEER="10.100.100.1"

MAX_RETRIES=5
RETRY_DELAY=3

# ==================================================
# PREVENT SIMULTANEOUS UPDATES
# ==================================================

exec 9>/run/update-gre.lock
flock -x 9


# ==================================================
# DETECT MIKROTIK PUBLIC IP
# ==================================================

SSH_INFO="${SSH_CONNECTION:-}"
NEW_IP="${SSH_INFO%% *}"

if [[ -z "$NEW_IP" ]]; then

    echo "ERROR: Unable to detect remote IP"
    echo "This script must be executed through SSH."

    exit 1

fi

# Validate public IPv4 address
python3 - "$NEW_IP" <<'PY'
import ipaddress
import sys

ip = ipaddress.IPv4Address(sys.argv[1])

if not ip.is_global:
    sys.exit("ERROR: Invalid public IPv4 address")
PY


# ==================================================
# CHECK NETPLAN CONFIGURATION
# ==================================================

if [[ ! -f "$CONFIG" ]]; then

    echo "ERROR: Netplan configuration not found"

    exit 1

fi

OLD_IP=$(netplan get tunnels.gre1.remote)

echo "======================================"
echo "         GRE Remote IP Update"
echo "======================================"

echo "Current Remote IP: $OLD_IP"
echo "New Remote IP    : $NEW_IP"


# ==================================================
# UPDATE GRE REMOTE IP
# ==================================================

if [[ "$OLD_IP" != "$NEW_IP" ]]; then

    # Backup current configuration
    cp -p "$CONFIG" "$BACKUP"

    echo "Backup created successfully."
    echo "Updating GRE configuration..."

    if netplan set --origin-hint=gre \
        "tunnels.gre1.remote=$NEW_IP" \
        && netplan generate \
        && netplan --debug apply; then

        echo ""
        echo "SUCCESS: GRE configuration updated"

        logger -t gre-update \
            "GRE remote updated: $OLD_IP -> $NEW_IP"

    else

        echo "ERROR: GRE configuration update failed"
        echo "Restoring previous configuration..."

        cp -p "$BACKUP" "$CONFIG"

        if netplan generate && netplan --debug apply; then

            echo "Previous configuration restored."

        else

            echo "CRITICAL: Automatic rollback failed."

        fi

        logger -t gre-update \
            "ERROR: GRE update failed: $OLD_IP -> $NEW_IP"

        exit 1

    fi

else

    echo "GRE remote IP is already correct."

fi


# ==================================================
# GRE TUNNEL HEALTH CHECK
# ==================================================

echo ""
echo "===== GRE Tunnel Health Check ====="

for ((i=1; i<=MAX_RETRIES; i++)); do

    echo ""
    echo "Health check attempt $i/$MAX_RETRIES"

    if ping -I "$GRE_INTERFACE" -c 3 -W 2 "$GRE_PEER"; then

        echo ""
        echo "======================================"
        echo "SUCCESS: GRE Tunnel is UP"
        echo "======================================"

        echo "Remote IP : $NEW_IP"
        echo "Interface : $GRE_INTERFACE"
        echo "GRE Peer  : $GRE_PEER"

        echo "======================================"

        logger -t gre-update \
            "SUCCESS: GRE tunnel established with $NEW_IP"

        exit 0

    fi

    if (( i < MAX_RETRIES )); then

        echo "Waiting $RETRY_DELAY seconds before retry..."
        sleep "$RETRY_DELAY"

    fi

done


# ==================================================
# HEALTH CHECK FAILED
# ==================================================

echo ""
echo "======================================"
echo "ERROR: GRE Tunnel is unreachable"
echo "======================================"

echo "Remote IP : $NEW_IP"
echo "Interface : $GRE_INTERFACE"
echo "GRE Peer  : $GRE_PEER"

echo "Configuration has been retained."
echo "No reboot performed."

echo "======================================"

logger -t gre-update \
    "ERROR: GRE health check failed for $NEW_IP"

exit 1

GREUPDATE

# Set script permissions
chown root:root /usr/local/sbin/update-gre.sh
chmod 700 /usr/local/sbin/update-gre.sh

# Validate script syntax
bash -n /usr/local/sbin/update-gre.sh

echo "GRE Auto Update Script installed successfully."
echo "Script: /usr/local/sbin/update-gre.sh"


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
# INSTALL AND CONFIGURE SNMP
# ==================================================

echo ""
echo "===== Install and Configure SNMP ====="

apt-get install -y snmpd snmp

# Backup existing SNMP configuration
if [[ -f /etc/snmp/snmpd.conf ]]; then

    cp -a /etc/snmp/snmpd.conf \
        "/etc/snmp/snmpd.conf.bak.$(date +%Y%m%d%H%M%S)"

fi

# Configure SNMP
cat > /etc/snmp/snmpd.conf <<'SNMPEOF'
rocommunity fan@solar
syslocation "Your Location"
syscontact victor.mohsen@gmail.com
SNMPEOF

# Enable and restart SNMP service
systemctl enable snmpd
systemctl restart snmpd

# Configure firewall if UFW is available
if command -v ufw >/dev/null 2>&1; then

    ufw allow 161/udp
    ufw reload

else

    echo "WARNING: UFW is not installed."
    echo "Ensure UDP port 161 is allowed if required."

fi

echo "SNMP configured successfully."


# ==================================================
# FINAL INSTALLATION REPORT
# ==================================================

echo ""
echo "======================================"
echo "Installation completed successfully!"
echo "======================================"

echo "GRE Local IP    : $LOCAL_IP"
echo "GRE Remote IP   : $REMOTE_IP"
echo "GRE Interface   : gre1"
echo "Tunnel IP       : 10.100.100.2/30"
echo "GRE Peer IP     : 10.100.100.1"
echo "GRE MTU         : 1400"

echo ""

echo "GRE Auto Update : Enabled on SSH request"
echo "Update Script   : /usr/local/sbin/update-gre.sh"
echo "Netplan Debug   : Enabled"
echo "Health Check    : Enabled"
echo "Health Retries  : 5"
echo "Auto Rollback   : Enabled"
echo "Update Reboot   : Disabled"

echo ""

echo "3X-UI           : Started"
echo "3X-UI Version   : v2.8.8"
echo "SNMP            : Configured"
echo "SNMP Port       : 161/UDP"

echo "======================================"
echo ""

echo "Installation completed."
echo "Rebooting in 10 seconds..."

sleep 10

reboot
