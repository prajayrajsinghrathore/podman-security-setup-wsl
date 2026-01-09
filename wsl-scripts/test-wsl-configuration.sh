#!/bin/bash
# Podman Security - WSL Configuration Test Script
# Comprehensive verification of all security configurations

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

PASS=0
FAIL=0

check() {
    local name="$1"
    local result="$2"
    if [ "$result" = "0" ]; then
        echo -e "${GREEN}[PASS]${NC} $name"
        ((PASS++))
    else
        echo -e "${RED}[FAIL]${NC} $name"
        ((FAIL++))
    fi
}

echo ""
echo "=== SSH Configuration ==="
ss -tlnp 2>/dev/null | grep -q "127.0.0.1:22"
check "SSH bound to localhost only" "$?"

grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null
check "SSH root login disabled" "$?"

grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null
check "SSH password auth disabled" "$?"

echo ""
echo "=== Podman Configuration ==="
podman info 2>/dev/null | grep -qi "rootless: true"
check "Podman rootless mode" "$?"

echo ""
echo "=== Repository Configuration ==="
test -f /etc/yum.repos.d/internal-mirror.repo
check "Internal mirror repo configured" "$?"

ls /etc/yum.repos.d/disabled/*.repo >/dev/null 2>&1
check "Public repos disabled" "$?"

echo ""
echo "=== Container Registry ==="
grep -q "blocked = true" /etc/containers/registries.conf 2>/dev/null
check "Public registries blocked" "$?"

echo ""
echo "=== Firewall Configuration ==="
if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --get-default-zone 2>/dev/null | grep -q "drop"
    check "Firewall default zone is drop" "$?"

    systemctl is-active firewalld >/dev/null 2>&1
    check "Firewalld service active" "$?"
else
    echo "[SKIP] Firewalld not installed"
fi

echo ""
echo "=== SELinux ==="
if command -v getenforce &>/dev/null; then
    [ "$(getenforce 2>/dev/null)" = "Enforcing" ]
    check "SELinux enforcing" "$?"
else
    echo "[SKIP] SELinux not available"
fi

echo ""
echo "=== DNS Configuration ==="
grep -q "nameserver" /etc/resolv.conf 2>/dev/null
check "DNS configured" "$?"

lsattr /etc/resolv.conf 2>/dev/null | grep -q "i"
check "resolv.conf immutable" "$?"

echo ""
echo "=== Patching Scripts ==="
test -x /opt/podman-security/scripts/update-system.sh
check "System update script exists" "$?"

test -x /opt/podman-security/scripts/health-check.sh
check "Health check script exists" "$?"

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

# Return failure count as exit code
exit $FAIL
