#!/bin/bash
# Podman Security - Linux Firewall Configuration
# This script configures Linux firewall to allow only internal network access

set -e

DNS_SERVER="{{DNS_SERVER}}"

echo "Configuring Linux firewall..."

# Install and enable firewalld if not present
if ! command -v firewall-cmd &>/dev/null; then
    echo "Installing firewalld..."
    dnf install -y firewalld 2>/dev/null || yum install -y firewalld 2>/dev/null || true
fi

# Start and enable firewalld
systemctl enable firewalld 2>/dev/null || true
systemctl start firewalld 2>/dev/null || true

# Configure firewall zones
echo "Setting default zone to drop..."
firewall-cmd --set-default-zone=drop 2>/dev/null || true

# Allow localhost
echo "Allowing localhost traffic..."
firewall-cmd --permanent --zone=trusted --add-source=127.0.0.0/8 2>/dev/null || true

# Allow internal DNS
echo "Allowing internal DNS..."
firewall-cmd --permanent --zone=trusted --add-source=${DNS_SERVER}/32 2>/dev/null || true

# Allow internal network ranges
echo "Allowing internal networks..."
firewall-cmd --permanent --zone=trusted --add-source=10.0.0.0/8 2>/dev/null || true
firewall-cmd --permanent --zone=trusted --add-source=172.16.0.0/12 2>/dev/null || true
firewall-cmd --permanent --zone=trusted --add-source=192.168.0.0/16 2>/dev/null || true

# Reload firewall
firewall-cmd --reload 2>/dev/null || true

echo "Firewall configuration:"
firewall-cmd --list-all 2>/dev/null || true

echo "Linux firewall configuration complete"
