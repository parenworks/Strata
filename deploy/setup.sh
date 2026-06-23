#!/usr/bin/env bash
# Strata deployment setup script
# Run once on the target server as a user with sudo access.
# Usage: bash deploy/setup.sh [options]
#
# Options (all have defaults):
#   --port       PORT       (default: 4242)
#   --db-name    NAME       (default: strata)
#   --db-user    USER       (default: strata)
#   --db-pass    PASS       (default: prompted)
#   --db-host    HOST       (default: localhost)
#   --bind-host  HOST       (default: 0.0.0.0)
#
# What this does:
#   1. Creates the PostgreSQL user and database
#   2. Builds the Strata binary via build.lisp
#   3. Installs the systemd service unit
#   4. Enables and starts the service

set -euo pipefail

STRATA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT=4242
DB_NAME=strata
DB_USER=strata
DB_PASS=""
DB_HOST=localhost
BIND_HOST=0.0.0.0
SERVICE_USER="$(whoami)"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)      PORT="$2";      shift 2 ;;
    --db-name)   DB_NAME="$2";   shift 2 ;;
    --db-user)   DB_USER="$2";   shift 2 ;;
    --db-pass)   DB_PASS="$2";   shift 2 ;;
    --db-host)   DB_HOST="$2";   shift 2 ;;
    --bind-host) BIND_HOST="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$DB_PASS" ]]; then
  read -rsp "PostgreSQL password for user '$DB_USER': " DB_PASS
  echo
fi

echo "==> Strata setup"
echo "    Directory : $STRATA_DIR"
echo "    Port      : $PORT"
echo "    DB        : $DB_USER@$DB_HOST/$DB_NAME"
echo "    Service   : strata (running as $SERVICE_USER)"
echo ""

# ------------------------------------------------------------------
# 1. PostgreSQL: create user + database
# ------------------------------------------------------------------
echo "==> Creating PostgreSQL user and database..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" \
  | grep -q 1 && echo "    User '$DB_USER' already exists." || \
  sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" \
  | grep -q 1 && echo "    Database '$DB_NAME' already exists." || \
  sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO $DB_USER;" 2>/dev/null || true

# ------------------------------------------------------------------
# 2. Ensure Fluxion is present and on the right branch
# ------------------------------------------------------------------
FLUXION_DIR="$(dirname "$STRATA_DIR")/Fluxion"
if [[ ! -d "$FLUXION_DIR/.git" ]]; then
  echo "==> Cloning Fluxion..."
  git clone git@github-parenworks:parenworks/Fluxion.git "$FLUXION_DIR"
fi
cd "$FLUXION_DIR"
git fetch origin
git checkout feature/database-layer
git pull origin feature/database-layer
cd "$STRATA_DIR"

# Register both repos with ASDF if not already done
SRCONF="$HOME/.config/common-lisp/source-registry.conf.d/strata.conf"
if [[ ! -f "$SRCONF" ]]; then
  echo "==> Writing ASDF source-registry config..."
  mkdir -p "$(dirname "$SRCONF")"
  cat > "$SRCONF" <<SREOF
(:tree "$FLUXION_DIR")
(:tree "$STRATA_DIR")
SREOF
fi

# ------------------------------------------------------------------
# 3. System dependencies
# ------------------------------------------------------------------
echo "==> Checking system dependencies..."
MISSING_PKGS=()
dpkg -s libev-dev &>/dev/null || MISSING_PKGS+=(libev-dev)
if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
  echo "    Installing: ${MISSING_PKGS[*]}"
  sudo apt-get install -y "${MISSING_PKGS[@]}"
else
  echo "    libev-dev already installed."
fi

# ------------------------------------------------------------------
# 4. Build binary
# ------------------------------------------------------------------
echo "==> Building Strata binary (this takes a minute)..."
mkdir -p "$STRATA_DIR/bin"
cd "$STRATA_DIR"
sbcl --noinform --disable-debugger --load build.lisp
echo "    Binary: $STRATA_DIR/bin/strata ($(du -sh bin/strata | cut -f1))"

# ------------------------------------------------------------------
# 4. Write VAPID config placeholder if missing
# ------------------------------------------------------------------
VAPID_FILE="$STRATA_DIR/config/vapid-keys.lisp"
if [[ ! -f "$VAPID_FILE" ]]; then
  echo "==> Generating VAPID keys via Strata..."
  mkdir -p "$STRATA_DIR/config"
  sbcl --noinform --disable-debugger \
    --eval '(asdf:load-system :strata)' \
    --eval '(strata.push:ensure-vapid-keys)' \
    --eval '(uiop:quit 0)' 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 4. Create uploads directory
# ------------------------------------------------------------------
mkdir -p "$STRATA_DIR/uploads"

# ------------------------------------------------------------------
# 5. Write systemd unit
# ------------------------------------------------------------------
UNIT_FILE="/etc/systemd/system/strata.service"
echo "==> Writing systemd unit to $UNIT_FILE ..."

sudo tee "$UNIT_FILE" > /dev/null <<EOF
[Unit]
Description=Strata chat server
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$STRATA_DIR
ExecStart=$STRATA_DIR/bin/strata \\
  --port $PORT \\
  --bind-host $BIND_HOST \\
  --db-name $DB_NAME \\
  --db-user $DB_USER \\
  --db-password $DB_PASS \\
  --db-host $DB_HOST
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=strata

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------------
# 6. Enable and start
# ------------------------------------------------------------------
echo "==> Enabling and starting strata service..."
sudo systemctl daemon-reload
sudo systemctl enable strata
sudo systemctl restart strata
sleep 3
sudo systemctl status strata --no-pager -l

echo ""
echo "==> Done. Strata is running on http://$(hostname -I | awk '{print $1}'):$PORT"
echo "    Logs:    journalctl -u strata -f"
echo "    Stop:    sudo systemctl stop strata"
echo "    Start:   sudo systemctl start strata"
echo "    Rebuild: bash $STRATA_DIR/deploy/rebuild.sh"
