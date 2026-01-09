#!/bin/bash
# Podman Security - SSH Security Configuration
# This script configures SSH to bind to localhost only with hardened security settings

set -e

echo "Configuring SSH security..."

# Backup original if not already done
if [ ! -f /etc/ssh/sshd_config.original ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.original 2>/dev/null || true
fi

# Create secure SSH configuration
cat > /etc/ssh/sshd_config << 'SSHEOF'
# Podman Security - SSH Configuration
# Generated: $(date)
# DO NOT MODIFY - Managed by Podman Security Setup

# ===========================================
# CRITICAL: Bind to localhost only
# ===========================================
ListenAddress 127.0.0.1
ListenAddress ::1
Port 22

# ===========================================
# Authentication Settings
# ===========================================
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# ===========================================
# Security Hardening
# ===========================================
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
GatewayPorts no
PermitUserEnvironment no

# ===========================================
# Connection Limits
# ===========================================
MaxAuthTries 3
MaxSessions 2
MaxStartups 2:30:10
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

# ===========================================
# Logging
# ===========================================
LogLevel VERBOSE
SyslogFacility AUTH

# ===========================================
# Cryptography
# ===========================================
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org

# ===========================================
# Subsystems
# ===========================================
Subsystem sftp /usr/libexec/openssh/sftp-server
SSHEOF

# Restart SSH service
systemctl restart sshd 2>/dev/null || service sshd restart 2>/dev/null || true

# Verify SSH is bound to localhost only
echo "Verifying SSH binding..."
ss -tlnp | grep ssh || netstat -tlnp | grep ssh || true

echo "SSH security configuration complete"
