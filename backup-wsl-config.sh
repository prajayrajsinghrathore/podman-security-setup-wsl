#!/bin/bash
# Podman Security - WSL Configuration Backup Script
# Backs up all WSL/Linux configurations before applying security settings

set -e

BACKUP_DIR="$1"

if [ -z "$BACKUP_DIR" ]; then
    echo "Error: Backup directory not specified"
    exit 1
fi

echo "Creating backup directories..."
mkdir -p "$BACKUP_DIR/containers" "$BACKUP_DIR/yum.repos.d"

echo "Backing up SSH configuration..."
[ -f /etc/ssh/sshd_config ] && cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.backup"

echo "Backing up repository configuration..."
cp /etc/yum.repos.d/*.repo "$BACKUP_DIR/yum.repos.d/" 2>/dev/null || true

echo "Backing up container configuration..."
[ -f /etc/containers/registries.conf ] && cp /etc/containers/registries.conf "$BACKUP_DIR/containers/"
[ -f /etc/containers/containers.conf ] && cp /etc/containers/containers.conf "$BACKUP_DIR/containers/"
[ -f /etc/containers/policy.json ] && cp /etc/containers/policy.json "$BACKUP_DIR/containers/"

echo "Backing up DNS configuration..."
[ -f /etc/resolv.conf ] && cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf.backup"

echo "Backing up user namespace configuration..."
[ -f /etc/subuid ] && cp /etc/subuid "$BACKUP_DIR/subuid.backup"
[ -f /etc/subgid ] && cp /etc/subgid "$BACKUP_DIR/subgid.backup"

echo "Backing up firewall configuration..."
command -v firewall-cmd &>/dev/null && firewall-cmd --list-all > "$BACKUP_DIR/firewall-config.txt" 2>/dev/null || true

echo "Backup complete"
