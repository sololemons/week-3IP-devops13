#!/bin/bash

# ==============================================================================
# Expected dirty conditions found in pre-provisioning audit:
# - Service accounts (kk-api, kk-payments, kk-logs) already exist: 
#   Handled in Phase 2 using idempotent id checks to skip creation.
# - Directory /opt/kijanikiosk/ and subdirs exist: 
#   Phase 3 will enforce correct ownership and verify the new /health directory.
# - Package holds (nginx, nodejs) are already active: 
#   Phase 1 will verify version alignment before attempting installation.
# - systemd units (kk-api, kk-payments) exist but lack hardening: 
#   Phase 4 will overwrite with production-grade specs (Target Score < 2.5).
# - ACLs on /shared/logs are present but require logrotate compatibility: 
#   Phase 7/8 will ensure default ACLs propagate to rotated files.
# ==============================================================================




set -euo pipefail

readonly NGINX_VERSION="1.24.0-2ubuntu7.6"   
readonly NODE_MAJOR_VERSION="20"
readonly APP_GROUP="kijanikiosk"
readonly APP_BASE="/opt/kijanikiosk"

log() {
  echo -e "\e[34m[INFO]\e[0m $1"
}

success() {
  
  echo -e "\e[32m[SUCCESS]\e[0m $1"
}

provision_packages() {
  log "=== Phase 1: Package Management (Strict Versioning) ==="

  local current_nginx
  current_nginx=$(dpkg-query -W -f='${Version}' nginx 2>/dev/null || echo "not_installed")

  if [[ "$current_nginx" != "not_installed" ]]; then
    if [[ "$current_nginx" == "$NGINX_VERSION" ]]; then
      log "Validated: Nginx is already at the pinned version ($NGINX_VERSION)."
    else
      echo -e "\e[31m[FATAL]\e[0m Nginx version mismatch detected!" >&2
      echo -e "       Installed: $current_nginx" >&2
      echo -e "       Required:  $NGINX_VERSION" >&2
      echo -e "Manual intervention required. Use 'apt-get install nginx=$NGINX_VERSION' manually if you must downgrade." >&2
      exit 1
    fi
  fi

  log "Updating package lists..."
  DEBIAN_FRONTEND=noninteractive apt-get update -qq

  log "Installing base dependencies (acl, ufw, gnupg)..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl gnupg acl ufw

  log "Configuring NodeSource repository..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR_VERSION}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
  
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  log "Applying version-pinned installations..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    nginx="${NGINX_VERSION}" nodejs

  log "Locking package versions (apt-mark hold)..."
  apt-mark hold nginx nodejs > /dev/null

  local actual_nginx=$(dpkg-query -W -f='${Version}' nginx)
  local actual_node=$(node -v)
  
  success "Package state verified. Nginx: ${actual_nginx} | Node: ${actual_node}"
}

provision_users() {
    log "=== Phase 2: Service Accounts ==="

    
    if getent group "${APP_GROUP}" >/dev/null 2>&1; then
        log "Validated: Group '${APP_GROUP}' already exists."
    else
        groupadd --system "${APP_GROUP}"
        success "Created: System group '${APP_GROUP}'."
    fi

   
    local accounts=("kk-api" "kk-payments" "kk-logs")
    for account in "${accounts[@]}"; do
        if ! id "${account}" >/dev/null 2>&1; then
            useradd --system --no-create-home --home-dir /nonexistent \
                --shell /usr/sbin/nologin \
                --comment "KijaniKiosk ${account} Service" \
                -g "${APP_GROUP}" "${account}"
            success "Created: Service user '${account}'."
        else
            log "Validated: Service user '${account}' already exists."
          
            usermod -aG "${APP_GROUP}" "${account}"
        fi
    done

    if id "lemonsthedev" >/dev/null 2>&1; then
        if id -nG "lemonsthedev" | grep -qw "${APP_GROUP}"; then
            log "Validated: User 'lemonsthedev' is already in ${APP_GROUP}."
        else
            usermod -aG "${APP_GROUP}" lemonsthedev
            success "Updated: Added existing user 'lemonsthedev' to ${APP_GROUP}."
        fi
    else
        log "User 'lemonsthedev' not found. Creating user..."
        
        useradd -m -s /bin/bash -g "${APP_GROUP}" lemonsthedev
        if [ $? -eq 0 ]; then
            success "Created: User 'lemonsthedev' with home directory."
        else
            echo "FATAL ERROR: Failed to create user 'lemonsthedev'. Halting!" >&2
            exit 1
        fi
    fi
}
provision_dirs() {
  log "=== Phase 3: Directory Architecture ==="

  log "Creating application directory..."
  mkdir -p "${APP_BASE}/api"
  mkdir -p "${APP_BASE}/payments"
  mkdir -p "${APP_BASE}/shared/logs"
  mkdir -p "${APP_BASE}/health"  
  mkdir -p "${APP_BASE}/config"   

  log "Setting ownership and strict base permissions..."

 
  chown kk-api:${APP_GROUP} "${APP_BASE}/api"
  chmod 750 "${APP_BASE}/api"
  chown kk-payments:${APP_GROUP} "${APP_BASE}/payments"
  chmod 750 "${APP_BASE}/payments"

  chown kk-logs:${APP_GROUP} "${APP_BASE}/shared/logs"
  chmod 775 "${APP_BASE}/shared/logs"

  chown root:${APP_GROUP} "${APP_BASE}/health"
  chmod 750 "${APP_BASE}/health"

  chown root:${APP_GROUP} "${APP_BASE}/config"
  chmod 755 "${APP_BASE}/config"

  log "Applying Access Control Lists (ACLs)..."

  
  setfacl -m u:kk-api:rwx,u:kk-payments:rwx "${APP_BASE}/shared/logs"
  setfacl -d -m u:kk-api:rwx,u:kk-payments:rwx "${APP_BASE}/shared/logs"

 
  setfacl -m g:${APP_GROUP}:rx "${APP_BASE}/health"
  setfacl -d -m g:${APP_GROUP}:r "${APP_BASE}/health"


  if [ ! -f "${APP_BASE}/config/payments-api.env" ]; then
    log "Deploying payments-api.env..."
    echo "PORT=3001" > "${APP_BASE}/config/payments-api.env"
    chown root:kk-payments "${APP_BASE}/config/payments-api.env"
    chmod 640 "${APP_BASE}/config/payments-api.env"
  fi

  success "Directories created with their permissions"
}

provision_services() {
  log "=== Phase 4: Deploying App Code & systemd ==="

  # This is where i have my put my javascript placeholder files since no was given 
  local SRC_DIR="/home/ubuntu/deploy"

  if [[ ! -d "$SRC_DIR" ]]; then
    log "ERROR: Source directory $SRC_DIR not found."
    return 1
  fi

  log "Deploying JavaScript source files..."
  install -o kk-api -g kijanikiosk -m 640 "${SRC_DIR}/api-server.js" "${APP_BASE}/api/server.js"
  install -o kk-payments -g kijanikiosk -m 640 "${SRC_DIR}/payment-service.js" "${APP_BASE}/payments/payment-service.js"

  if [[ -f "${SRC_DIR}/log-service.js" ]]; then
      install -o kk-logs -g kijanikiosk -m 640 "${SRC_DIR}/log-service.js" "${APP_BASE}/shared/logs/log-service.js"
  else
      # Fallback dummy script just so the service doesn't crash if the file is missing in lab as we were not given this in our previous labs 
      echo "console.log('Log service placeholder running...'); setInterval(() => {}, 60000)" > "${APP_BASE}/shared/logs/log-service.js"
      chown kk-logs:kijanikiosk "${APP_BASE}/shared/logs/log-service.js"
      chmod 640 "${APP_BASE}/shared/logs/log-service.js"
  fi

echo "PORT=3000" > "${APP_BASE}/config/kk-api.env"
chown root:${APP_GROUP} "${APP_BASE}/config/kk-api.env"
chmod 640 "${APP_BASE}/config/kk-api.env"


echo "PORT=3001" > "${APP_BASE}/config/payments-api.env"
chown root:${APP_GROUP} "${APP_BASE}/config/payments-api.env"
chmod 640 "${APP_BASE}/config/payments-api.env"

echo "LOG_LEVEL=info" > "${APP_BASE}/config/kk-logs.env"
chown root:${APP_GROUP} "${APP_BASE}/config/kk-logs.env"
chmod 640 "${APP_BASE}/config/kk-logs.env"

  log "Writing kk-api.service..."
  cat > /etc/systemd/system/kk-api.service << 'UNIT'
[Unit]
Description=KijaniKiosk API Service
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=kk-api
Group=kijanikiosk
WorkingDirectory=/opt/kijanikiosk/api
ExecStart=/usr/bin/node /opt/kijanikiosk/api/server.js
EnvironmentFile=/opt/kijanikiosk/config/kk-api.env
Restart=on-failure
RestartSec=5

# === 1. Filesystem Sandboxing ===
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ReadOnlyPaths=/opt/kijanikiosk/api
ReadOnlyPaths=/opt/kijanikiosk/config/kk-api.env
ReadWritePaths=/opt/kijanikiosk/shared/logs
InaccessiblePaths=/root /boot /home /run/user

# === 2. Privilege Restriction ===
NoNewPrivileges=yes
CapabilityBoundingSet=
RestrictSUIDSGID=yes
RestrictRealTIME=yes

# === 3. Kernel & Resource Protection ===
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
ProtectKernelLogs=yes
ProtectClock=yes
RestrictNamespaces=yes
LockPersonality=yes

# === 4. System Call Filtering  ===
# Only allow standard service calls and network I/O
SystemCallFilter=@system-service @network-io @signal @timer
SystemCallErrorNumber=EPERM

# === 5. Network Sandboxing ===
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=multi-user.target
UNIT

  log "Writing kk-payments.service..."
  cat > /etc/systemd/system/kk-payments.service << 'UNIT'
[Unit]
Description=KijaniKiosk Payments Service
After=network.target kk-api.service
Wants=kk-api.service
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=kk-payments
Group=kijanikiosk
WorkingDirectory=/opt/kijanikiosk/payments
ExecStart=/usr/bin/node /opt/kijanikiosk/payments/payment-service.js
EnvironmentFile=/opt/kijanikiosk/config/payments-api.env
Restart=on-failure
RestartSec=5

# Aggressive Hardening
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

ReadWritePaths=/opt/kijanikiosk/shared/logs
ReadOnlyPaths=/opt/kijanikiosk/config/payments-api.env

PrivateDevices=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes

NoNewPrivileges=yes
CapabilityBoundingSet=
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

SystemCallErrorNumber=EPERM
SystemCallFilter=@system-service @network-io @signal @timer


RestrictNamespaces=yes
LockPersonality=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes

RestrictNamespaces=yes
ProtectKernelLogs=yes
ProtectClock=yes

[Install]
WantedBy=multi-user.target
UNIT

  log "Writing kk-logs.service..."
  cat > /etc/systemd/system/kk-logs.service << 'UNIT'
[Unit]
Description=KijaniKiosk Logs Service
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=kk-logs
Group=kijanikiosk
WorkingDirectory=/opt/kijanikiosk/shared/logs
ExecStart=/usr/bin/node /opt/kijanikiosk/shared/logs/log-service.js
EnvironmentFile=/opt/kijanikiosk/config/kk-logs.env
Restart=on-failure
RestartSec=5

# === Filesystem Hardening ===
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ReadOnlyPaths=/opt/kijanikiosk/config/kk-logs.env
ReadWritePaths=/opt/kijanikiosk/shared/logs
InaccessiblePaths=/root /boot /home

# === Privilege Hardening ===
NoNewPrivileges=yes
CapabilityBoundingSet=
RestrictSUIDSGID=yes

# === Kernel & System Hardening ===
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
ProtectKernelLogs=yes
ProtectClock=yes
RestrictNamespaces=yes
LockPersonality=yes

# === System Call Filtering ===
SystemCallFilter=@system-service @network-io @signal @timer
SystemCallErrorNumber=EPERM

[Install]
WantedBy=multi-user.target
UNIT

 
  log "Reloading systemd and starting services..."
  systemctl daemon-reload

  systemctl enable --now kk-api.service
  systemctl enable --now kk-payments.service
  systemctl enable --now kk-logs.service

  success "All services deployed. Dependency links and Hardening applied."
}
provision_logging() {
  log "=== Phase 7: Journal Persistence and Log Rotation ==="
  
  log "Configuring persistent journald storage..."
  mkdir -p /var/log/journal
  systemd-tmpfiles --create --prefix /var/log/journal

  mkdir -p /etc/systemd/journald.conf.d/
  cat > /etc/systemd/journald.conf.d/kijanikiosk.conf << 'CONF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=500M
SystemMaxFileSize=50M
CONF

  systemctl restart systemd-journald
  success "Persistent journal configured for max 500MB."

  
  log "Writing logrotate configuration for application logs..."
  cat > /etc/logrotate.d/kijanikiosk << 'EOF'
/opt/kijanikiosk/shared/logs/*.log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    su root kijanikiosk
    create 0660 kk-logs kijanikiosk
    sharedscripts
    postrotate
        /usr/bin/systemctl kill -s HUP kk-logs.service >/dev/null 2>&1 || true
        /usr/bin/systemctl kill -s HUP kk-payments.service >/dev/null 2>&1 || true
        /usr/bin/systemctl kill -s HUP kk-api.service >/dev/null 2>&1 || true
    endscript
}
EOF
  success "Logrotate configuration written."
}

provision_firewall() {
  log "=== Phase 5: Resetting and Configuring UFW (Intent-Based) ==="

  log "Resetting UFW to baseline..."
  ufw --force reset >/dev/null 2>&1

 
  ufw default deny incoming
  ufw default allow outgoing

  log "Applying loopback rules..."
  ufw allow from 127.0.0.1 to any port 3001 proto tcp comment "Allow Nginx proxy to kk-payments"

  
  log "Applying strict CIDR allow rules..."
  ufw allow from 10.0.1.0/24 to any port 22 proto tcp comment "Allow SSH from Monitoring Subnet"
  ufw allow from 10.0.1.0/24 to any port 80 proto tcp comment "Allow HTTP from Monitoring Subnet"
  ufw allow from 10.0.1.0/24 to any port 3001 proto tcp comment "Allow kk-payments health check from Monitoring Subnet"

 
  log "Applying explicit denies..."
  ufw deny to any port 3001 proto tcp comment "Explicitly deny external kk-payments access"

  log "Enabling UFW..."
  ufw --force enable >/dev/null 2>&1

  success "UFW configured with deliberate intent and comments."
}

verify_state() {
  log "=== Phase 8: Verification & Health Checks ==="
  local failed=0

  log "Verifying service accounts..."
  local accounts=("kk-api" "kk-payments" "kk-logs")
  for account in "${accounts[@]}"; do
    if id "${account}" >/dev/null 2>&1; then
      success "Account exists: ${account}"
    else
      log "FAIL: Account missing: ${account}"
      ((failed++))
    fi
  done

  log "Verifying application directories..."
  local dirs=("${APP_BASE}/api" "${APP_BASE}/payments" "${APP_BASE}/shared/logs")
  for dir in "${dirs[@]}"; do
    if [[ -d "${dir}" ]]; then
      success "Directory exists: ${dir}"
    else
      log "FAIL: Directory missing: ${dir}"
      ((failed++))
    fi
  done

  log "Scanning for dangerous SUID files..."
  local suid_files=$(find "${APP_BASE}" -type f -perm -4000 2>/dev/null)
  if [[ -z "${suid_files}" ]]; then
    success "No SUID files found in application tree."
  else
    log "FAIL: Dangerous SUID files found!"
    echo "${suid_files}"
    ((failed++))
  fi

  log "Verifying package holds..."
  local held_packages=$(apt-mark showhold)
  for pkg in nginx nodejs; do
    if echo "${held_packages}" | grep -qw "${pkg}"; then
      success "Package held: ${pkg}"
    else
      log "FAIL: Package NOT held: ${pkg}"
      ((failed++))
    fi
  done

  local api_status="DOWN"
  local payments_status="DOWN"

  log "Verifying API service..."
  if systemctl is-enabled --quiet kk-api.service; then
    success "Service enabled: kk-api.service"
  else
    log "FAIL: Service NOT enabled: kk-api.service"
    ((failed++))
  fi
   
  if ss -tln | grep -q ":3000"; then
    success "Network: Service is listening on port 3000"
    api_status="UP"
  else
    log "FAIL: Nothing is listening on port 3000"
    ((failed++))
  fi

  log "Verifying Payments service..."
  if systemctl is-enabled --quiet kk-payments.service; then
    success "Service enabled: kk-payments.service"
  else
    log "FAIL: Service NOT enabled: kk-payments.service"
    ((failed++))
  fi

  if ss -tln | grep -q ":3001"; then
    success "Network: Service is listening on port 3001"
    payments_status="UP"
  else
    log "FAIL: Nothing is listening on port 3001"
    ((failed++))
  fi
  log "Verifying Logs service..."
  local logs_status="DOWN"

  if systemctl is-enabled --quiet kk-logs.service; then
    success "Service enabled: kk-logs.service"
  else
    log "FAIL: Service NOT enabled: kk-logs.service"
    ((failed++))
  fi
  if systemctl is-active --quiet kk-logs.service; then
    success "Process:kk-logs.service is actively running"
    logs_status="UP"
  else
    log "FAIL: Service is NOT running: kk-logs.service"
    ((failed++))
  fi
 
  log "Writing health check JSON file..."
  local HEALTH_DIR="${APP_BASE}/health"
  mkdir -p "${HEALTH_DIR}"
  local JSON_FILE="${HEALTH_DIR}/last-provision.json"
  local TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > "${JSON_FILE}" << EOF
{
  "timestamp": "${TIMESTAMP}",
  "services": {
    "kk-api": {
      "port": 3000,
      "status": "${api_status}"
    },
    "kk-payments": {
      "port": 3001,
      "status": "${payments_status}"
    },
   "kk-logs": {
      "status": "${logs_status}"
    }
  }
}
EOF
  chown root:${APP_GROUP} "${HEALTH_DIR}"
  chown root:${APP_GROUP} "${JSON_FILE}"
  chmod 750 "${HEALTH_DIR}"
  chmod 640 "${JSON_FILE}"
  success "Health check JSON written to ${JSON_FILE}"

  
  log "Verifying logrotate configuration syntax..."
  if logrotate --debug /etc/logrotate.d/kijanikiosk >/dev/null 2>&1; then
    success "Logrotate config passed debug check."
  else
    log "FAIL: Logrotate config has syntax errors."
    ((failed++))
  fi

  log "Verifying access model survives logrotate."
  logrotate --force /etc/logrotate.d/kijanikiosk >/dev/null 2>&1 || true
  
  if sudo -u kk-api touch "${APP_BASE}/shared/logs/test-write.tmp" 2>/dev/null; then
    success "PASS: kk-api can write to shared/logs after rotation"
    rm -f "${APP_BASE}/shared/logs/test-write.tmp"
  else
    log "FAIL: kk-api cannot write to shared/logs after rotation (ACLs broken!)"
    ((failed++))
  fi


  log "Verifying UFW ruleset programmatically..."

  local UFW_RULES=$(ufw status verbose)


  if echo "$UFW_RULES" | grep -q "3001/tcp.*ALLOW IN.*127.0.0.1"; then
    success "PASS: Firewall allows 3001 from loopback"
  else
    log "FAIL: Firewall missing loopback rule for 3001"
    ((failed++))
  fi

 
  if echo "$UFW_RULES" | grep -q "22/tcp.*ALLOW IN.*10.0.1.0/24"; then
    success "PASS: Firewall allows SSH specifically from 10.0.1.0/24"
  else
    log "FAIL: Firewall missing strict SSH rule"
    ((failed++))
  fi

  if echo "$UFW_RULES" | grep -q "3001/tcp.*DENY IN.*Anywhere"; then
    success "PASS: Firewall explicitly denies 3001 from Anywhere"
  else
    log "FAIL: Firewall missing explicit deny for 3001"
    ((failed++))
  fi

  log "=== Verification Summary ==="
  if [[ ${failed} -eq 0 ]]; then
    success "All verification checks passed! Server is ready."
  else
    log "CRITICAL: ${failed} verification check(s) failed - review output above."
    exit 1
  fi
}

provision_packages    # Phase 1
provision_users       # Phase 2
provision_dirs        # Phase 3
provision_logging     # Phase 4
provision_services    # Phase 5
provision_firewall    # Phase 6
verify_state          # Phase 7

log "Provisioning complete!"

