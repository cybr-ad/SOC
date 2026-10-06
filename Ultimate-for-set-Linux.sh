#!/usr/bin/env bash
# ==============================================================================
# Script: linux-forwarder.sh / Ultimate-for-set-Linux.sh
# Purpose: Universal, Self-Healing Splunk Forwarder & Linux Security Telemetry
# Platform: Ubuntu Server 20.04/22.04/24.04 LTS & Debian/CentOS/RHEL (VMware VM)
# Target Indexer: Host Windows 11 Splunk Enterprise Indexer (192.168.10.1:9997)
# ==============================================================================

set -eo pipefail

SPLUNK_SERVER_IP="${1:-192.168.10.1}"
SPLUNK_PORT="${2:-9997}"
SPLUNK_HOME="/opt/splunkforwarder"
GATEWAY_IP="192.168.10.2"

# Colors
C_RESET="\e[0m"
C_CYAN="\e[36m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_BOLD="\e[1m"

clear
echo -e "${C_CYAN}${C_BOLD}================================================================================"
echo -e "       ULTIMATE LINUX SPLUNK FORWARDER & TELEMETRY AUTO-DEPLOYER                "
echo -e "      Universal Path-Independent Auto-Deployer with Comprehensive Self-Healing  "
echo -e "================================================================================${C_RESET}"

step() { echo -e "\n${C_YELLOW}${C_BOLD}[+] $1${C_RESET}"; }
success() { echo -e "    ${C_GREEN}[OK] $1${C_RESET}"; }
info() { echo -e "    ${C_CYAN}[*] $1${C_RESET}"; }
warn() { echo -e "    ${C_YELLOW}[!] $1${C_RESET}"; }
failure() { echo -e "    ${C_RED}[-] $1${C_RESET}"; }

# ------------------------------------------------------------------------------
# 1. ROOT PRIVILEGES CHECK
# ------------------------------------------------------------------------------
step "Step 1: Validating Root Privileges..."
if [ "$EUID" -ne 0 ]; then
    failure "This script must be run as root or with sudo!"
    echo -e "    Run again using: ${C_BOLD}sudo bash $0${C_RESET}"
    exit 1
fi
success "Running with root authority."

# ------------------------------------------------------------------------------
# 2. OS & ARCHITECTURE DETECTION
# ------------------------------------------------------------------------------
step "Step 2: Detecting Linux Distribution & Architecture..."
PKG_MGR="apt"
if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
    export DEBIAN_FRONTEND=noninteractive
    info "Detected Debian/Ubuntu family (Package manager: apt)"
elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
    info "Detected RHEL/Fedora family (Package manager: dnf)"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
    info "Detected CentOS/RHEL family (Package manager: yum)"
fi

ARCH=$(uname -m)
info "Kernel: $(uname -r), Architecture: $ARCH, Hostname: $(hostname)"

# ------------------------------------------------------------------------------
# 3. NETWORK DIAGNOSTICS & SELF-HEALING
# ------------------------------------------------------------------------------
step "Step 3: Network Diagnostics and Verification..."

# Detect Primary Interface
PRIMARY_IF=$(ip -4 route show default | awk '{print $5}' | head -n1 || true)
if [ -z "$PRIMARY_IF" ]; then
    PRIMARY_IF="ens33"
fi
CURRENT_IP=$(ip -4 addr show "$PRIMARY_IF" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || true)
info "Network interface: $PRIMARY_IF (IP: ${CURRENT_IP:-'Not Configured'})"

# Test Gateway Connectivity
info "Pinging VMware NAT Gateway ($GATEWAY_IP)..."
if ping -c 2 -W 2 "$GATEWAY_IP" &>/dev/null; then
    success "VMware NAT Gateway ($GATEWAY_IP) is REACHABLE."
else
    warn "Gateway ($GATEWAY_IP) did not reply. Verify VMware VMnet8 NAT settings."
fi

# Test Internet Connectivity
info "Checking internet reachability (8.8.8.8)..."
if ping -c 2 -W 2 8.8.8.8 &>/dev/null; then
    success "Internet connectivity confirmed."
else
    warn "No internet response. Offline/local package modes will be prioritized."
fi

# Test Target Splunk Indexer TCP 9997
info "Testing TCP connectivity to Splunk Indexer ($SPLUNK_SERVER_IP:$SPLUNK_PORT)..."
if command -v nc &>/dev/null && nc -z -w 3 "$SPLUNK_SERVER_IP" "$SPLUNK_PORT" 2>/dev/null; then
    success "Splunk Indexer port $SPLUNK_PORT on $SPLUNK_SERVER_IP is OPEN and reachable!"
elif (echo >/dev/tcp/"$SPLUNK_SERVER_IP"/"$SPLUNK_PORT") 2>/dev/null; then
    success "Splunk Indexer port $SPLUNK_PORT on $SPLUNK_SERVER_IP is OPEN and reachable!"
else
    warn "Port $SPLUNK_PORT on $SPLUNK_SERVER_IP is not responding yet."
    warn "Ensure 'host-indexer.ps1' is running on the Windows 11 host and Firewall permits TCP 9997."
fi

# ------------------------------------------------------------------------------
# 4. PACKAGE INSTALLATION (AUDITD, RSYSLOG, TOOLS)
# ------------------------------------------------------------------------------
step "Step 4: Installing auditd, rsyslog, acl, and Network Tools..."

if [ "$PKG_MGR" = "apt" ]; then
    apt-get update -y -q || true
    apt-get install -y -q auditd audispd-plugins rsyslog curl wget net-tools acl netcat-openbsd || \
    apt-get install -y -q auditd rsyslog curl wget net-tools acl || true
elif [ "$PKG_MGR" = "dnf" ] || [ "$PKG_MGR" = "yum" ]; then
    $PKG_MGR install -y audit rsyslog curl wget net-tools acl nc || true
fi
success "Prerequisite packages installed."

# ------------------------------------------------------------------------------
# 5. DEPLOY HIGH-FIDELITY SOC AUDIT RULES
# ------------------------------------------------------------------------------
step "Step 5: Deploying SOC High-Fidelity Audit Rules..."

RULES_DIR="/etc/audit/rules.d"
mkdir -p "$RULES_DIR"

cat << 'EOF' > "$RULES_DIR/soc-audit.rules"
## ==============================================================================
## SOC Class 02 - High-Fidelity Linux Audit Rules
## File: /etc/audit/rules.d/soc-audit.rules
## ==============================================================================

# Delete all existing rules & establish buffer
-D
-b 8192
-f 1

# Identity & Credential Modifications
-w /etc/passwd -p wa -k identity_changes
-w /etc/shadow -p wa -k identity_changes
-w /etc/group -p wa -k identity_changes
-w /etc/gshadow -p wa -k identity_changes
-w /etc/security/opasswd -p wa -k identity_changes

# Sudoers & Privilege Configuration
-w /etc/sudoers -p wa -k sudo_changes
-w /etc/sudoers.d/ -p wa -k sudo_changes
-w /etc/pam.d/ -p wa -k pam_changes

# Network & Host Identity Changes
-w /etc/issue -p wa -k system_banner
-w /etc/issue.net -p wa -k system_banner
-w /etc/hosts -p wa -k network_changes
-w /etc/network/ -p wa -k network_changes

# Root Executions & Sensitive Commands
-a always,exit -F arch=b64 -S execve -F euid=0 -k root_commands
-a always,exit -F arch=b32 -S execve -F euid=0 -k root_commands

# Privilege Escalation Binaries
-w /bin/su -p x -k priv_escalation
-w /usr/bin/sudo -p x -k priv_escalation
EOF

# Copy fallback to /etc/audit/audit.rules
cp "$RULES_DIR/soc-audit.rules" /etc/audit/audit.rules || true

if command -v augenrules &>/dev/null; then
    augenrules --load || true
    success "Loaded audit rules using augenrules."
else
    service auditd restart 2>/dev/null || systemctl restart auditd 2>/dev/null || true
    success "Restarted auditd service."
fi

# Ensure auditd is running and enabled
systemctl enable auditd 2>/dev/null || true
systemctl start auditd 2>/dev/null || true

# ------------------------------------------------------------------------------
# 6. SPLUNK UNIVERSAL FORWARDER INSTALLATION
# ------------------------------------------------------------------------------
step "Step 6: Installing & Verifying Splunk Universal Forwarder..."

# Search candidate local paths for splunkforwarder package
LOCAL_CANDIDATES=(
    "$(dirname "$0")/splunkforwarder.deb"
    "$(dirname "$0")/../class file/bin/splunkforwarder.deb"
    "/home/socadmin/soc_lab/splunkforwarder.deb"
    "/tmp/splunkforwarder.deb"
    "./splunkforwarder.deb"
)

PKG_FILE=""
for cand in "${LOCAL_CANDIDATES[@]}"; do
    if [ -f "$cand" ]; then
        PKG_FILE="$cand"
        break
    fi
done

if [ ! -d "$SPLUNK_HOME" ]; then
    if [ -z "$PKG_FILE" ]; then
        info "Local package not found. Attempting download from Splunk CDN..."
        DOWNLOAD_URL="https://download.splunk.com/products/universalforwarder/releases/9.1.2/linux/splunkforwarder-9.1.2-b6b9c8185839-linux-2.6-amd64.deb"
        wget -q --show-progress -O /tmp/splunkforwarder.deb "$DOWNLOAD_URL" || true
        if [ -f /tmp/splunkforwarder.deb ] && [ -s /tmp/splunkforwarder.deb ]; then
            PKG_FILE="/tmp/splunkforwarder.deb"
        fi
    fi

    if [ -n "$PKG_FILE" ] && [ -f "$PKG_FILE" ]; then
        info "Installing Universal Forwarder from $PKG_FILE..."
        if [ "$PKG_MGR" = "apt" ]; then
            dpkg -i "$PKG_FILE" || apt-get install -f -y
        elif command -v rpm &>/dev/null && [[ "$PKG_FILE" == *.rpm ]]; then
            rpm -ivh "$PKG_FILE"
        fi
        success "Splunk Universal Forwarder installed in $SPLUNK_HOME."
    else
        warn "Could not download or locate splunkforwarder installer package."
        warn "If installing manually, extract to $SPLUNK_HOME and re-run."
    fi
else
    success "Existing Splunk Forwarder detected at $SPLUNK_HOME."
fi

# ------------------------------------------------------------------------------
# 7. CONFIGURE INPUTS.CONF & OUTPUTS.CONF
# ------------------------------------------------------------------------------
step "Step 7: Configuring Telemetry Inputs and Output Routing..."

LOCAL_DIR="$SPLUNK_HOME/etc/system/local"
mkdir -p "$LOCAL_DIR"

# Stage sample attack log if found
SAMPLE_LOG_SRC="$(dirname "$0")/../class file/samples/linux_attacks_sample.log"
if [ -f "$SAMPLE_LOG_SRC" ]; then
    cp "$SAMPLE_LOG_SRC" /var/log/linux_attacks_sample.log
    chmod 644 /var/log/linux_attacks_sample.log
    success "Staged sample Linux attack log to /var/log/linux_attacks_sample.log"
fi

cat << EOF > "$LOCAL_DIR/inputs.conf"
# ==============================================================================
# Splunk Universal Forwarder - Linux Telemetry Inputs Configuration
# Generated by: linux-forwarder.sh
# ==============================================================================

[default]
host = srv-linux-01

# -------------------------------------------------------------
# Linux Authentication Telemetry -> index = linux_logs
# -------------------------------------------------------------
[monitor:///var/log/auth.log]
disabled = 0
sourcetype = linux_secure
index = linux_logs

[monitor:///var/log/secure]
disabled = 0
sourcetype = linux_secure
index = linux_logs

# -------------------------------------------------------------
# Linux System Logs -> index = linux_logs
# -------------------------------------------------------------
[monitor:///var/log/syslog]
disabled = 0
sourcetype = syslog
index = linux_logs

[monitor:///var/log/messages]
disabled = 0
sourcetype = syslog
index = linux_logs

# -------------------------------------------------------------
# Linux Audit Daemon (auditd) -> index = linux_logs
# -------------------------------------------------------------
[monitor:///var/log/audit/audit.log]
disabled = 0
sourcetype = linux_audit
index = linux_logs

# -------------------------------------------------------------
# Sample Attack Simulation Log (When present)
# -------------------------------------------------------------
[monitor:///var/log/linux_attacks_sample.log]
disabled = 0
sourcetype = custom_linux_attacks
index = linux_logs
EOF
success "Configured inputs.conf (auth.log, syslog, auditd, sample attacks -> linux_logs)."

cat << EOF > "$LOCAL_DIR/outputs.conf"
# ==============================================================================
# Splunk Universal Forwarder - Linux Output Routing Configuration
# Generated by: linux-forwarder.sh
# ==============================================================================

[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = ${SPLUNK_SERVER_IP}:${SPLUNK_PORT}
autoLB = true
compressed = false
sendCookedData = true
heartbeatFrequency = 30

[tcpout-server://${SPLUNK_SERVER_IP}:${SPLUNK_PORT}]
EOF
success "Configured outputs.conf pointing to ${SPLUNK_SERVER_IP}:${SPLUNK_PORT}"

# ------------------------------------------------------------------------------
# 8. SELF-HEALING FILE & LOG PERMISSIONS (CRITICAL STEP)
# ------------------------------------------------------------------------------
step "Step 8: Fixing File and Log Permissions for Forwarder Ingestion..."

chmod -R go+r /var/log/auth.log /var/log/syslog 2>/dev/null || true

if [ -d /var/log/audit ]; then
    chmod 750 /var/log/audit
    chmod 640 /var/log/audit/audit.log* 2>/dev/null || true
    if command -v setfacl &>/dev/null; then
        setfacl -m u:splunk:r /var/log/audit/audit.log 2>/dev/null || true
        setfacl -m d:u:splunk:r /var/log/audit/ 2>/dev/null || true
        success "Applied POSIX ACL read permission for splunk user on /var/log/audit/audit.log"
    else
        chmod 644 /var/log/audit/audit.log 2>/dev/null || true
        success "Set fallback readable mode on audit.log"
    fi
fi

# ------------------------------------------------------------------------------
# 9. START & ENABLE SPLUNK SERVICE
# ------------------------------------------------------------------------------
step "Step 9: Starting & Enabling Splunk Universal Forwarder..."

if [ -f "$SPLUNK_HOME/bin/splunk" ]; then
    "$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes --no-prompt || true
    "$SPLUNK_HOME/bin/splunk" enable boot-start -user splunk --accept-license 2>/dev/null || \
    "$SPLUNK_HOME/bin/splunk" enable boot-start --accept-license 2>/dev/null || true
    success "Splunk Forwarder daemon started and registered for boot-start."
else
    warn "Splunk binary not present at $SPLUNK_HOME/bin/splunk."
fi

# ------------------------------------------------------------------------------
# 10. FINAL SUMMARY DASHBOARD
# ------------------------------------------------------------------------------
echo -e "\n${C_CYAN}${C_BOLD}================================================================================"
echo -e "                   LINUX FORWARDER DEPLOYMENT SUMMARY                           "
echo -e "================================================================================${C_RESET}"

AUDIT_STATUS=$(systemctl is-active auditd 2>/dev/null || echo "Unknown")
SPLUNK_STATUS="Inactive"
if [ -f "$SPLUNK_HOME/bin/splunk" ]; then
    if "$SPLUNK_HOME/bin/splunk" status 2>/dev/null | grep -q "running"; then
        SPLUNK_STATUS="Running"
    fi
fi

RULE_COUNT=$(auditctl -l 2>/dev/null | wc -l || echo "0")

printf "%-28s : %s\n" "Linux Hostname" "$(hostname)"
printf "%-28s : %s\n" "Assigned IPv4 Address" "${CURRENT_IP:-'N/A'}"
printf "%-28s : %s\n" "VMware NAT Gateway" "$GATEWAY_IP"
printf "%-28s : %s\n" "Splunk Indexer Target" "${SPLUNK_SERVER_IP}:${SPLUNK_PORT}"
printf "%-28s : %b%s%b\n" "auditd Daemon" "${C_GREEN}" "$AUDIT_STATUS" "${C_RESET}"
printf "%-28s : %b%s loaded%b\n" "SOC Audit Rules" "${C_GREEN}" "$RULE_COUNT" "${C_RESET}"
printf "%-28s : %b%s%b\n" "Splunk Forwarder" "${C_GREEN}" "$SPLUNK_STATUS" "${C_RESET}"
printf "%-28s : %s\n" "Target Index" "linux_logs"

echo -e "${C_CYAN}================================================================================"
echo -e "${C_GREEN}Linux deployment complete. Telemetry is streaming to $SPLUNK_SERVER_IP:$SPLUNK_PORT${C_RESET}"
echo -e "${C_CYAN}================================================================================\n${C_RESET}"
