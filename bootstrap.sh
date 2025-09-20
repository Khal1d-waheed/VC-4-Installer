#!/bin/bash
set -euo pipefail

# ==================================================
# Crestron VC-4 Installation Bootstrap Wrapper
# ==================================================
# 1. Validates OS compatibility & root access
# 2. Installs system-level prerequisites
# 3. Ensures Python 3.9 & pip
# 4. Creates Python 3.9 venv & installs dependencies
# 5. Extracts Crestron VC4 package from same directory
# 6. Removes conflicting 32-bit libs
# 7. Copies to safe dir & runs "installVC4.sh"
# 8. Applies Crestron sysctl tuning
# 9. Configures SNMP for VC-4 monitoring
# 10. Checks license status (Licensed / Trial / Missing / Expired)
# 11. Prompts for license if invalid/missing (file path OR paste)
# 12. Waits for WebApp port + health-check
# 13. Prints Crestron’s expected access URL
# ==================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="/opt/vc4-wrapper/venv"
LOGFILE="/var/log/vc4_wrapper.log"
SAFE_DIR="/opt/vc4-install-tmp"
LICENSE_FILE="/opt/crestron/virtualcontrol/licenses/cert.0.pem"

# --------------------------------------------------
# Require root
# --------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./bootstrap.sh)"
  exit 1
fi

# --------------------------------------------------
# Logging
# --------------------------------------------------
exec > >(tee -i "$LOGFILE") 2>&1
echo "=== Crestron VC-4 Installation Wrapper ==="
echo "Logging to $LOGFILE"

# --------------------------------------------------
# Step 1: OS Compatibility
# --------------------------------------------------
if grep -Eq "Red Hat Enterprise Linux.*8\.[2-9]|Red Hat Enterprise Linux.*9|AlmaLinux.*8\.[3-9]|AlmaLinux.*9|Rocky Linux.*8\.[4-9]|Rocky Linux.*9" /etc/redhat-release; then
  echo "Detected compatible OS: $(cat /etc/redhat-release)"
else
  echo "Unsupported OS. Need RHEL 8.2+/9, AlmaLinux 8.3+/9, Rocky 8.4+/9"
  exit 1
fi

# --------------------------------------------------
# Step 2: System prerequisites
# --------------------------------------------------
echo "Installing system prerequisites..."
yum install -y unzip tar net-tools iproute firewalld iptables \
  policycoreutils policycoreutils-python-utils selinux-policy selinux-policy-targeted \
  net-snmp net-snmp-utils curl

# --------------------------------------------------
# Step 2.5: Remove known conflicts
# --------------------------------------------------
if rpm -q perl-libs.i686 >/dev/null 2>&1; then
  echo "Removing conflicting 32-bit perl-libs.i686..."
  yum remove -y perl-libs.i686
fi

# --------------------------------------------------
# Step 3: Python 3.9
# --------------------------------------------------
if ! command -v python3.9 &>/dev/null; then
  echo "Installing Python 3.9..."
  dnf module reset -y python36 || true
  dnf module enable -y python39
  yum install -y python39 python39-pip python39-devel
fi

# --------------------------------------------------
# Step 4: Python 3.9 venv
# --------------------------------------------------
echo "Creating venv with Python 3.9 at $VENV_DIR"
if [ -d "$VENV_DIR" ]; then
  echo "Removing old venv"
  rm -rf "$VENV_DIR"
fi
python3.9 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel

# --------------------------------------------------
# Step 5: Python Dependencies
# --------------------------------------------------
echo "Installing Python dependencies..."
pip install \
  alembic==1.13.1 \
  aniso8601==9.0.1 \
  certifi==2024.6.2 \
  click==8.1.7 \
  eventlet==0.36.1 \
  Flask==2.3.3 \
  Flask-JWT==0.3.2 \
  Flask-JWT-Extended==2.4.1 \
  Flask-RESTful==0.3.10 \
  Flask-SocketIO==5.3.6 \
  greenlet==3.0.3 \
  grpcio==1.64.1 \
  grpcio-tools==1.64.1 \
  macholib==1.16.3 \
  pefile==2023.2.7 \
  pyasn1==0.6.0 \
  PyJWT==1.4.2 \
  pyparsing==3.1.2 \
  packaging==24.1 \
  pysmb==1.2.9.1 \
  python-dateutil==2.9.0.post0 \
  python-editor==1.0.4 \
  python-socketio==5.11.3 \
  flask-sqlalchemy==3.1.1 \
  SQLAlchemy==2.0.31 \
  SQLAlchemy-Utils==0.41.2 \
  urllib3==1.26.19 \
  virtualenv==20.26.3 \
  Werkzeug==3.0.3 \
  redis==5.0.6 \
  pymysql==1.1.1

# --------------------------------------------------
# Step 6: Locate Crestron Archive
# --------------------------------------------------
ARCHIVE=$(find "$SCRIPT_DIR" -maxdepth 1 -type f \
  \( -name "*.zip" -o -name "*.tar.gz" -o -name "*.tgz" -o -name "*.tar" \) | head -n 1 || true)

if [ -z "$ARCHIVE" ]; then
  echo "No Crestron package archive found in $(pwd)"
  echo "Please place the Crestron .zip/.tar.gz/.tar in the same folder as bootstrap.sh"
  exit 1
fi

echo "Found Crestron archive: $ARCHIVE"
echo "Extracting package..."
case "$ARCHIVE" in
  *.zip)    unzip -o "$ARCHIVE" -d "$SCRIPT_DIR" ;;
  *.tar.gz) tar -xvzf "$ARCHIVE" -C "$SCRIPT_DIR" ;;
  *.tgz)    tar -xvzf "$ARCHIVE" -C "$SCRIPT_DIR" ;;
  *.tar)    tar -xvf "$ARCHIVE" -C "$SCRIPT_DIR" ;;
esac

# --------------------------------------------------
# Step 7: Run Crestron Installer
# --------------------------------------------------
INSTALL_SCRIPT=$(find "$SCRIPT_DIR" -type f -name "installVC4.sh" | head -n 1 || true)

if [ -z "$INSTALL_SCRIPT" ]; then
  echo "Could not find 'installVC4.sh' inside extracted package"
  exit 1
fi

rm -rf "$SAFE_DIR"
mkdir -p "$SAFE_DIR"

echo "Copying extracted Crestron package to $SAFE_DIR"
cp -r "$(dirname "$INSTALL_SCRIPT")"/* "$SAFE_DIR/"

echo "Running Crestron installer from $SAFE_DIR"
chmod +x "$SAFE_DIR/installVC4.sh"
(
  cd "$SAFE_DIR"
  ./installVC4.sh
)

echo ">>> Crestron VC-4 installation completed successfully."

# --------------------------------------------------
# Step 8: Apply Crestron sysctl tuning
# --------------------------------------------------
SYSCTL_FILE="/etc/sysctl.conf"
echo "Applying Crestron sysctl tuning..."
for setting in \
  "net.ipv4.tcp_keepalive_intvl=30" \
  "net.ipv4.tcp_keepalive_time=30" \
  "net.ipv4.tcp_retries2=8"; do
  if ! grep -q "^$setting" "$SYSCTL_FILE" 2>/dev/null; then
    echo "$setting" >> "$SYSCTL_FILE"
  fi
done

sysctl -p

echo ">>> Sysctl tuning applied. Current values:"
sysctl net.ipv4.tcp_keepalive_intvl
sysctl net.ipv4.tcp_keepalive_time
sysctl net.ipv4.tcp_retries2

# --------------------------------------------------
# Step 9: Configure SNMP
# --------------------------------------------------
SNMP_CONF="/etc/snmp/snmpd.conf"

if [ -f "$SNMP_CONF" ]; then
  if ! grep -q "agentXSocket tcp:localhost:705" "$SNMP_CONF"; then
    echo "Configuring SNMP for VC-4..."
    echo "" >> "$SNMP_CONF"
    echo "master agentx" >> "$SNMP_CONF"
    echo "agentXSocket tcp:localhost:705" >> "$SNMP_CONF"
  else
    echo "SNMP already configured for VC-4."
  fi
else
  echo "SNMP config file not found, creating new one..."
  mkdir -p /etc/snmp
  echo "master agentx" > "$SNMP_CONF"
  echo "agentXSocket tcp:localhost:705" >> "$SNMP_CONF"
fi

systemctl enable snmpd.service
systemctl restart snmpd.service

# --------------------------------------------------
# Step 10: License Status Check
# --------------------------------------------------
check_license_status() {
  local status
  status=$(curl -s "http://localhost:3030/api/license/status" || true)
  if echo "$status" | grep -qi "valid"; then
    echo "VALID"
  elif echo "$status" | grep -qi "trial"; then
    echo "TRIAL"
  elif echo "$status" | grep -qi "expired"; then
    echo "EXPIRED"
  else
    echo "UNKNOWN"
  fi
}

NEED_LICENSE=false
echo "Checking VC-4 license status..."
if [ ! -s "$LICENSE_FILE" ]; then
  echo "License Status: MISSING"
  NEED_LICENSE=true
else
  if grep -q "BEGIN CERTIFICATE" "$LICENSE_FILE"; then
    case "$(check_license_status)" in
      VALID)   echo "License Status: VALID" ;;
      TRIAL)   echo "License Status: TRIAL" ;;
      EXPIRED) echo "License Status: EXPIRED"; NEED_LICENSE=true ;;
      *)       echo "License Status: UNKNOWN"; NEED_LICENSE=true ;;
    esac
  else
    echo "License Status: INVALID (corrupt cert file)"
    NEED_LICENSE=true
  fi
fi

# --------------------------------------------------
# Step 11: Prompt for License if Needed + Re-Check Loop
# --------------------------------------------------
if [ "$NEED_LICENSE" = true ]; then
  echo "-------------------------------------------------"
  echo "Your VC-4 installation needs a valid license."
  echo "Options:"
  echo "  1) Enter full path to license file"
  echo "  2) Paste license text directly (multi-line, finish with Ctrl+D)"
  read -rp "Enter license file path or type 'paste': " INPUT

  if [ "$INPUT" = "paste" ]; then
    echo "Paste your license certificate below. When finished, press Ctrl+D:"
    TMPFILE=$(mktemp)
    cat > "$TMPFILE"
    mv "$TMPFILE" "$LICENSE_FILE"
  elif [ -n "$INPUT" ] && [ -f "$INPUT" ]; then
    cp "$INPUT" "$LICENSE_FILE"
  else
    echo "No license provided. VC-4 may run in limited or trial mode."
  fi

  echo "Restarting VC-4 service..."
  systemctl restart virtualcontrol.service

  echo "Re-checking license status (up to 2 minutes)..."
  for i in {1..12}; do
    sleep 10
    STATUS=$(check_license_status)
    if [ "$STATUS" = "VALID" ]; then
      echo "License Status: VALID"
      NEED_LICENSE=false
      break
    fi
    echo "[$i/12] License not valid yet, retrying..."
  done

  if [ "$NEED_LICENSE" = true ]; then
    echo "License still not valid after retries. Please check manually."
  fi
fi

# --------------------------------------------------
# Step 12: Wait for WebApp
# --------------------------------------------------
echo "Waiting for VC-4 WebApp to start..."
VC4_PORT=""
STATUS=""
for i in {1..30}; do
  VC4_PORT=$(ss -tulpn 2>/dev/null | grep -E 'node|VirtualControl|webApp' | awk '{print $5}' | grep -oE '[0-9]+$' | head -n 1 || true)
  if [ -n "$VC4_PORT" ]; then
    SERVER_IP=$(hostname -I | awk '{for(i=1;i<=NF;i++){if($i !~ /^127/ && $i !~ /^192\.168\.122/){print $i; exit}}}')
    SERVER_IP=${SERVER_IP:-localhost}
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP:$VC4_PORT/VirtualControl/config/settings/" || true)
    if [ "$STATUS" = "200" ]; then
      echo "VC-4 WebApp is up and responding on port $VC4_PORT"
      break
    fi
  fi
  echo "[$i/30] WebApp not ready yet (port=$VC4_PORT, status=${STATUS:-N/A}), retrying in 10s..."
  sleep 10
done

if [ -z "$VC4_PORT" ] || [ "$STATUS" != "200" ]; then
  echo "Error: VC-4 WebApp did not become ready after 5 minutes"
  exit 1
fi

# --------------------------------------------------
# Step 13: Print Final Access URL
# --------------------------------------------------
echo "================================================="
echo "VC-4 Installation Completed Successfully"
echo "Logs saved to $LOGFILE"
echo "Access VC-4 via:"
echo "  → http://$SERVER_IP/VirtualControl/config/settings/"
echo "  (Backend confirmed on port $VC4_PORT with HTTP 200)"
echo "================================================="
