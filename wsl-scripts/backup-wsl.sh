#!/bin/bash
# backup-wsl.sh
# Backs up WSL configuration files for Podman security setup
# Used by Backup-PodmanConfig.ps1 via Invoke-ExternalBashScript

set -e

BACKUP_DIR="{{BACKUP_DIR}}"

echo "Creating backup directories..."
mkdir -p "$BACKUP_DIR/containers"
mkdir -p "$BACKUP_DIR/yum.repos.d"

echo ""
echo "=== SSH Configuration ==="
if [ -f /etc/ssh/sshd_config ]; then
    cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.backup"
    echo "Backed up: /etc/ssh/sshd_config"
else
    echo "Not found: /etc/ssh/sshd_config (skipping)"
fi

echo ""
echo "=== Repository Configuration ==="
if [ -d /etc/yum.repos.d ]; then
    cp /etc/yum.repos.d/*.repo "$BACKUP_DIR/yum.repos.d/" 2>/dev/null || echo "No .repo files found"
    echo "Backed up: /etc/yum.repos.d/*.repo"
fi

echo ""
echo "=== Container Configuration ==="
if [ -f /etc/containers/registries.conf ]; then
    cp /etc/containers/registries.conf "$BACKUP_DIR/containers/"
    echo "Backed up: /etc/containers/registries.conf"
fi

if [ -f /etc/containers/containers.conf ]; then
    cp /etc/containers/containers.conf "$BACKUP_DIR/containers/"
    echo "Backed up: /etc/containers/containers.conf"
fi

if [ -f /etc/containers/policy.json ]; then
    cp /etc/containers/policy.json "$BACKUP_DIR/containers/"
    echo "Backed up: /etc/containers/policy.json"
fi

echo ""
echo "=== DNS Configuration ==="
if [ -f /etc/resolv.conf ]; then
    # Remove immutable flag temporarily if set
    chattr -i /etc/resolv.conf 2>/dev/null || true
    cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf.backup"
    echo "Backed up: /etc/resolv.conf"
fi

echo ""
echo "=== User Namespace Configuration ==="
if [ -f /etc/subuid ]; then
    cp /etc/subuid "$BACKUP_DIR/subuid.backup"
    echo "Backed up: /etc/subuid"
fi

if [ -f /etc/subgid ]; then
    cp /etc/subgid "$BACKUP_DIR/subgid.backup"
    echo "Backed up: /etc/subgid"
fi

echo ""
echo "=== Firewall Configuration ==="
if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --list-all > "$BACKUP_DIR/firewall-config.txt" 2>/dev/null || echo "Could not export firewall config"
    firewall-cmd --get-default-zone > "$BACKUP_DIR/firewall-zone.txt" 2>/dev/null || true
    echo "Backed up: firewall configuration"
else
    echo "Firewalld not installed (skipping)"
fi

echo ""
echo "=== Environment Configuration ==="
if [ -f /etc/environment ]; then
    cp /etc/environment "$BACKUP_DIR/environment.backup"
    echo "Backed up: /etc/environment"
fi

if [ -f /etc/dnf/dnf.conf ]; then
    cp /etc/dnf/dnf.conf "$BACKUP_DIR/dnf.conf.backup"
    echo "Backed up: /etc/dnf/dnf.conf"
fi

echo ""
echo "=== Backup Manifest ==="
echo "Backup completed at: $(date)" > "$BACKUP_DIR/manifest.txt"
echo "Files backed up:" >> "$BACKUP_DIR/manifest.txt"
find "$BACKUP_DIR" -type f -name "*.backup" -o -name "*.txt" -o -name "*.conf" -o -name "*.repo" 2>/dev/null | sort >> "$BACKUP_DIR/manifest.txt"

echo ""
echo "WSL backup complete!"
