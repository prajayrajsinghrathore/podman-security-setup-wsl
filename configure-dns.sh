#!/bin/bash
# Podman Security - DNS Configuration
# This script configures DNS to use internal DNS server only

set -e

DNS_SERVER="{{DNS_SERVER}}"

echo "Configuring DNS..."

# Remove immutable flag if set
chattr -i /etc/resolv.conf 2>/dev/null || true

# Backup original
cp /etc/resolv.conf /etc/resolv.conf.podman-backup 2>/dev/null || true

# Create new resolv.conf
cat > /etc/resolv.conf << DNSEOF
# Podman Security - DNS Configuration
# Generated: $(date)
# DO NOT MODIFY - Managed by Podman Security Setup
# File is immutable - use chattr -i to modify

nameserver ${DNS_SERVER}
search internal.company.com
options timeout:2 attempts:2
DNSEOF

# Make file immutable to prevent WSL from overwriting
chattr +i /etc/resolv.conf 2>/dev/null || true

echo "DNS configuration complete"
cat /etc/resolv.conf
