#!/bin/bash
# Podman Security - Configuration Verification Script
# This script verifies that all security configurations are properly applied

PASS=0
FAIL=0

check() {
    if [ $? -eq 0 ]; then
        echo "[PASS] $1"
        ((PASS++))
    else
        echo "[FAIL] $1"
        ((FAIL++))
    fi
}

echo "=== Verification ==="
ss -tlnp 2>/dev/null | grep -q "127.0.0.1:22"; check "SSH bound to localhost"
podman info 2>/dev/null | grep -qi "rootless: true"; check "Podman rootless mode"
test -f /etc/yum.repos.d/internal-mirror.repo; check "Internal mirror configured"
grep -q "blocked = true" /etc/containers/registries.conf 2>/dev/null; check "Public registries blocked"
firewall-cmd --get-default-zone 2>/dev/null | grep -q "drop"; check "Firewall zone is drop"
test -x /opt/podman-security/scripts/update-system.sh; check "Patching scripts deployed"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
