#!/usr/bin/env bash
#
# SOC Class 02 - Ubuntu srv-linux-01 all-in-one setup
#
# Implements the updated lab manual:
#   Static IP  : 192.168.10.30/24
#   Gateway    : 192.168.10.2
#   DNS        : 192.168.10.20, 1.1.1.1
#   Hostname   : srv-linux-01
#   Splunk     : 192.168.10.1:9997
#   Logs       : /var/log/auth.log, /var/log/audit/audit.log
#   User       : socadmin
#   Forwarder  : Splunk Universal Forwarder 9.1.2
#
# Run as root:
#   sudo bash linux.sh
#

set -Eeuo pipefail
IFS=$'\n\t'

# ----------------------------- Lab variables -----------------------------
HOSTNAME_VALUE="srv-linux-01"
STATIC_IP="192.168.10.30/24"
GATEWAY_IP="192.168.10.2"
DNS1="192.168.10.20"
DNS2="1.1.1.1"
SPLUNK_SERVER="192.168.10.1"
SPLUNK_PORT="9997"
SPLUNK_UF_VERSION="9.1.2"
SPLUNK_UF_FILE="splunkforwarder-9.1.2-b6b9c8185839-linux-2.6-amd64.deb"
SPLUNK_UF_URL="https://download.splunk.com/products/universalforwarder/releases/9.1.2/linux/${SPLUNK_UF_FILE}"
SPLUNK_HOME="/opt/splunkforwarder"
SOC_USER="socadmin"
SOC_PASSWORD="P@ssw0rd2026!"
SPLUNK_SERVICE_USER="splunk"
NETPLAN_FILE="/etc/netplan/99-soc-lab.yaml"
BACKUP_DIR="/root/soc_lab_backup_$(date +%Y%m%d-%H%M%S)"
SAMPLE_LOG="/var/log/linux_attacks_sample.log"

# Optional first argument can override interface, otherwise detect default route.
IFACE="${1:-}"

log(){ printf '\n[+] %s\n' "$1"; }
ok(){ printf '    [OK] %s\n' "$1"; }
warn(){ printf '    [!] %s\n' "$1" >&2; }

cleanup_on_error(){
    warn "Setup failed at line $1. Existing network config was backed up under ${BACKUP_DIR} when applicable."
}
trap 'cleanup_on_error $LINENO' ERR

require_root(){
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "Run as root: sudo bash linux.sh" >&2
        exit 1
    fi
}

ensure_command(){
    command -v "$1" >/dev/null 2>&1 || {
        echo "Required command '$1' is missing." >&2
        exit 1
    }
}

detect_interface(){
    if [[ -n "$IFACE" ]] && ip link show "$IFACE" >/dev/null 2>&1; then
        return
    fi
    IFACE="$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')"
    if [[ -z "$IFACE" ]]; then
        # Updated manual normally uses ens33 under VMware.
        IFACE="ens33"
    fi
    if ! ip link show "$IFACE" >/dev/null 2>&1; then
        echo "Could not find network interface '$IFACE'. Run: ip link" >&2
        exit 1
    fi
}

backup_network(){
    mkdir -p "$BACKUP_DIR"
    if compgen -G '/etc/netplan/*.yaml' >/dev/null 2>&1; then
        cp -a /etc/netplan/*.yaml "$BACKUP_DIR/" || true
    fi
}

configure_hostname(){
    log "Configuring hostname"
    hostnamectl set-hostname "$HOSTNAME_VALUE"
    grep -qE "\s${HOSTNAME_VALUE}$" /etc/hosts || printf '127.0.1.1 %s\n' "$HOSTNAME_VALUE" >> /etc/hosts
    ok "Hostname = $(hostname)"
}

configure_static_ip(){
    log "Configuring static IPv4 via Netplan"
    backup_network
    detect_interface

    cat > "$NETPLAN_FILE" <<EOF_NETPLAN
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses:
        - ${STATIC_IP}
      routes:
        - to: default
          via: ${GATEWAY_IP}
      nameservers:
        addresses:
          - ${DNS1}
          - ${DNS2}
EOF_NETPLAN

    chmod 600 "$NETPLAN_FILE"

    if command -v netplan >/dev/null 2>&1; then
        netplan generate
        # 'try' can require interactive confirmation; use apply for this lab script.
        netplan apply
    else
        echo 'netplan is not installed; install it with: apt-get install -y netplan.io' >&2
        exit 1
    fi

    ok "Interface = $IFACE"
    ok "Address   = $STATIC_IP"
    ok "Gateway   = $GATEWAY_IP"
    ok "DNS       = $DNS1, $DNS2"
}

install_packages(){
    log "Installing Ubuntu packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y \
        auditd \
        audispd-plugins \
        acl \
        curl \
        wget \
        netcat-openbsd \
        openssh-server \
        open-vm-tools \
        rsyslog \
        ca-certificates
    ok 'Required packages installed.'
}

configure_hosts(){
    log "Adding lab host mappings"
    ensure_hosts_line(){
        local ip="$1"; local name="$2"; shift 2
        if ! grep -qE "^${ip}[[:space:]]" /etc/hosts; then
            printf '%s\t%s %s\n' "$ip" "$name" "$*" >> /etc/hosts
        fi
    }
    ensure_hosts_line "192.168.10.20" "dc01-corp.corp.local" "dc01-corp"
    ensure_hosts_line "192.168.10.1" "splunk-host" "splunk"
    ok '/etc/hosts updated for lab nodes.'
}

configure_user(){
    log "Creating/verifying SOC user: $SOC_USER"
    if ! id "$SOC_USER" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$SOC_USER"
    fi
    echo "${SOC_USER}:${SOC_PASSWORD}" | chpasswd
    usermod -aG sudo "$SOC_USER"
    ok "User $SOC_USER exists and is in sudo group."
}

configure_services(){
    log "Enabling SSH, rsyslog, auditd and VMware Tools"
    systemctl enable --now ssh || systemctl enable --now ssh.service
    systemctl enable --now rsyslog
    systemctl enable --now auditd || true
    systemctl enable --now open-vm-tools
    ok 'Core services enabled.'
}

configure_audit_rules(){
    log "Configuring auditd file-change rules"
    mkdir -p /etc/audit/rules.d
    cat > /etc/audit/rules.d/99-soc-lab.rules <<'EOF_AUDIT'
# SOC lab identity / privilege change monitoring
-w /etc/passwd -p wa -k identity_changes
-w /etc/shadow -p wa -k identity_changes
-w /etc/group -p wa -k identity_changes
-w /etc/gshadow -p wa -k identity_changes
-w /etc/sudoers -p wa -k identity_changes
-w /etc/sudoers.d/ -p wa -k identity_changes

# Authentication/security configuration monitoring
-w /etc/ssh/sshd_config -p wa -k ssh_config_changes
EOF_AUDIT

    if command -v augenrules >/dev/null 2>&1; then
        augenrules --load || true
    fi
    systemctl restart auditd || true
    ok 'auditd identity_changes rules written.'
}

install_forwarder(){
    log "Installing Splunk Universal Forwarder ${SPLUNK_UF_VERSION}"

    if [[ -x "${SPLUNK_HOME}/bin/splunk" ]]; then
        ok 'Splunk Universal Forwarder is already installed.'
        return
    fi

    local deb="/tmp/${SPLUNK_UF_FILE}"
    wget -O "$deb" "$SPLUNK_UF_URL"
    dpkg -i "$deb"
    rm -f "$deb"

    if [[ ! -d "$SPLUNK_HOME" ]]; then
        echo "Splunk Universal Forwarder installation did not create $SPLUNK_HOME" >&2
        exit 1
    fi
    ok 'Splunk Universal Forwarder installed.'
}

configure_splunk_user(){
    log "Configuring dedicated Splunk service account"
    if ! id "$SPLUNK_SERVICE_USER" >/dev/null 2>&1; then
        useradd --system --home "$SPLUNK_HOME" --shell /usr/sbin/nologin "$SPLUNK_SERVICE_USER"
    fi
    chown -R "$SPLUNK_SERVICE_USER:$SPLUNK_SERVICE_USER" "$SPLUNK_HOME"
    ok "Splunk files owned by $SPLUNK_SERVICE_USER."
}

write_splunk_configs(){
    log "Writing Splunk inputs.conf and outputs.conf"
    local local_dir="${SPLUNK_HOME}/etc/system/local"
    mkdir -p "$local_dir"

    cat > "${local_dir}/inputs.conf" <<EOF_INPUTS
[default]
host = ${HOSTNAME_VALUE}

[monitor:///var/log/auth.log]
disabled = false
sourcetype = linux_secure
index = linux_logs

[monitor:///var/log/audit/audit.log]
disabled = false
sourcetype = linux_audit
index = linux_logs

[monitor:::${SAMPLE_LOG}]
disabled = false
sourcetype = custom_linux_attacks
index = linux_logs
crcSalt = <SOURCE>
EOF_INPUTS

    # Fix monitor stanza typo intentionally avoided by writing a proper path stanza below.
    sed -i "s#\[monitor:::${SAMPLE_LOG}\]#[monitor://${SAMPLE_LOG}]#" "${local_dir}/inputs.conf"

    cat > "${local_dir}/outputs.conf" <<EOF_OUTPUTS
[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = ${SPLUNK_SERVER}:${SPLUNK_PORT}

[tcpout-server://${SPLUNK_SERVER}:${SPLUNK_PORT}]
EOF_OUTPUTS

    chmod 640 "${local_dir}/inputs.conf" "${local_dir}/outputs.conf"
    chown "$SPLUNK_SERVICE_USER:$SPLUNK_SERVICE_USER" "${local_dir}/inputs.conf" "${local_dir}/outputs.conf"

    ok "Forward target = ${SPLUNK_SERVER}:${SPLUNK_PORT}"
    ok 'Monitors = /var/log/auth.log, /var/log/audit/audit.log'
}

prepare_log_files(){
    log "Preparing log locations and Splunk read permissions"

    # Ensure rsyslog creates auth.log on systems where it is not present yet.
    touch /var/log/auth.log
    chmod 640 /var/log/auth.log || true
    chown root:adm /var/log/auth.log || true

    touch "$SAMPLE_LOG"
    chmod 640 "$SAMPLE_LOG"
    chown root:adm "$SAMPLE_LOG" || true

    if command -v setfacl >/dev/null 2>&1; then
        setfacl -m "u:${SPLUNK_SERVICE_USER}:r" /var/log/auth.log
        setfacl -m "u:${SPLUNK_SERVICE_USER}:r" /var/log/audit/audit.log 2>/dev/null || true
        setfacl -m "u:${SPLUNK_SERVICE_USER}:r" "$SAMPLE_LOG"
    else
        chmod 644 /var/log/auth.log "$SAMPLE_LOG" || true
        chmod 644 /var/log/audit/audit.log 2>/dev/null || true
    fi

    ok "auth log     = /var/log/auth.log"
    ok "audit log    = /var/log/audit/audit.log"
    ok "sample log   = $SAMPLE_LOG"
}

start_splunk(){
    log "Starting and enabling Splunk Universal Forwarder"
    if [[ ! -x "${SPLUNK_HOME}/bin/splunk" ]]; then
        echo "Splunk binary missing: ${SPLUNK_HOME}/bin/splunk" >&2
        exit 1
    fi

    chown -R "$SPLUNK_SERVICE_USER:$SPLUNK_SERVICE_USER" "$SPLUNK_HOME"

    if ! sudo -u "$SPLUNK_SERVICE_USER" "$SPLUNK_HOME/bin/splunk" status >/dev/null 2>&1; then
        sudo -u "$SPLUNK_SERVICE_USER" "$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes || true
    fi

    "$SPLUNK_HOME/bin/splunk" enable boot-start -user "$SPLUNK_SERVICE_USER" || true

    if systemctl list-unit-files | grep -q '^SplunkForwarder.service'; then
        systemctl enable --now SplunkForwarder
    elif [[ -x "$SPLUNK_HOME/bin/splunk" ]]; then
        sudo -u "$SPLUNK_SERVICE_USER" "$SPLUNK_HOME/bin/splunk" restart || true
    fi

    ok 'Splunk Universal Forwarder start/boot configuration completed.'
}

health_check(){
    log "Running Linux forwarder health check"

    echo
    echo '--- Network ---'
    ip a show "$IFACE" || true
    ip route || true

    echo
    echo '--- Connectivity ---'
    ping -c 2 -W 2 "$GATEWAY_IP" || warn "Gateway ping failed."
    ping -c 2 -W 2 "$SPLUNK_SERVER" || warn "Splunk host ping failed."
    if nc -zvw 3 "$SPLUNK_SERVER" "$SPLUNK_PORT"; then
        ok "TCP ${SPLUNK_SERVER}:${SPLUNK_PORT} reachable."
    else
        warn "TCP ${SPLUNK_SERVER}:${SPLUNK_PORT} is NOT reachable."
    fi

    echo
    echo '--- Services ---'
    systemctl is-active auditd || true
    systemctl is-active rsyslog || true
    systemctl is-active open-vm-tools || true
    systemctl is-active ssh || true

    echo
    echo '--- Splunk ---'
    sudo -u "$SPLUNK_SERVICE_USER" "$SPLUNK_HOME/bin/splunk" status || true
    sudo -u "$SPLUNK_SERVICE_USER" "$SPLUNK_HOME/bin/splunk" list forward-server || true
    sudo -u "$SPLUNK_SERVICE_USER" "$SPLUNK_HOME/bin/splunk" list monitor || true
}

main(){
    require_root
    ensure_command ip
    ensure_command apt-get

    log 'SOC CLASS 02 - UBUNTU ALL-IN-ONE SETUP'
    echo "Hostname      : $HOSTNAME_VALUE"
    echo "Static IP     : $STATIC_IP"
    echo "Gateway       : $GATEWAY_IP"
    echo "DNS           : $DNS1, $DNS2"
    echo "Splunk target : ${SPLUNK_SERVER}:${SPLUNK_PORT}"
    echo

    configure_hostname
    install_packages
    detect_interface
    configure_static_ip
    configure_hosts
    configure_user
    configure_services
    configure_audit_rules
    install_forwarder
    configure_splunk_user
    write_splunk_configs
    prepare_log_files
    start_splunk
    health_check

    log 'SETUP COMPLETE'
    ok "Hostname = $HOSTNAME_VALUE"
    ok "IP = $STATIC_IP"
    ok "Splunk target = ${SPLUNK_SERVER}:${SPLUNK_PORT}"
    ok 'Logs = /var/log/auth.log + /var/log/audit/audit.log'
    ok "User = $SOC_USER"
    echo
    echo 'Next manual checks:'
    echo '  sudo /opt/splunkforwarder/bin/splunk status'
    echo '  sudo /opt/splunkforwarder/bin/splunk list forward-server'
    echo '  sudo /opt/splunkforwarder/bin/splunk list monitor'
    echo '  nc -zv 192.168.10.1 9997'
}

main "$@"
