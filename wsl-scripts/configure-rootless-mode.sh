#!/bin/bash
# Podman Security - Rootless Mode Configuration
# This script configures Podman to run in rootless mode with security hardening

set -e

echo "Configuring rootless Podman..."

# Get the primary non-root user
PRIMARY_USER=$(getent passwd 1000 | cut -d: -f1)
if [ -z "$PRIMARY_USER" ]; then
    PRIMARY_USER="podmanuser"
    echo "Creating podmanuser..."
    useradd -m -s /bin/bash podmanuser 2>/dev/null || true
fi

echo "Configuring for user: $PRIMARY_USER"

# Configure subuid/subgid for rootless containers
if ! grep -q "^${PRIMARY_USER}:" /etc/subuid 2>/dev/null; then
    echo "${PRIMARY_USER}:100000:65536" >> /etc/subuid
fi
if ! grep -q "^${PRIMARY_USER}:" /etc/subgid 2>/dev/null; then
    echo "${PRIMARY_USER}:100000:65536" >> /etc/subgid
fi

# Create containers.conf with security settings
mkdir -p /etc/containers
cat > /etc/containers/containers.conf << 'CONTEOF'
# Podman Security - Container Configuration
# Generated: $(date)
# DO NOT MODIFY - Managed by Podman Security Setup

[containers]
# ===========================================
# User Namespace (Rootless)
# ===========================================
userns = "auto"
ipcns = "private"
utsns = "private"
cgroupns = "private"

# ===========================================
# Resource Limits
# ===========================================
pids_limit = 2048
log_size_max = 104857600
shm_size = "64m"

# ===========================================
# Security Options
# ===========================================
no_new_privileges = true
default_sysctls = [
    "net.ipv4.ping_group_range=0 0",
]

# ===========================================
# Capability Restrictions
# ===========================================
default_capabilities = [
    "CHOWN",
    "DAC_OVERRIDE",
    "FOWNER",
    "FSETID",
    "KILL",
    "NET_BIND_SERVICE",
    "SETFCAP",
    "SETGID",
    "SETPCAP",
    "SETUID",
]

# ===========================================
# Security Labels (SELinux)
# ===========================================
label = true
label_type = "container_t"

[engine]
# ===========================================
# Engine Security Settings
# ===========================================
cgroup_manager = "systemd"
events_logger = "journald"
runtime = "crun"

# Disable privileged containers by default
# (can be overridden with --privileged if explicitly needed)

[network]
# ===========================================
# Network Security
# ===========================================
default_network = "podman"
network_backend = "netavark"
CONTEOF

# Enable SELinux if available
if command -v getenforce &>/dev/null; then
    echo "Configuring SELinux..."
    setenforce 1 2>/dev/null || true
    sed -i 's/SELINUX=permissive/SELINUX=enforcing/' /etc/selinux/config 2>/dev/null || true
    sed -i 's/SELINUX=disabled/SELINUX=enforcing/' /etc/selinux/config 2>/dev/null || true
fi

# Verify rootless configuration
echo "Verifying rootless configuration..."
echo "subuid entries:"
cat /etc/subuid
echo "subgid entries:"
cat /etc/subgid

echo "Rootless mode configuration complete"
