#!/bin/bash
# Podman Security - Proxy Configuration
# This script configures system-wide and Podman-specific proxy settings

set -e

PROXY_URL="{{PROXY_URL}}"

echo "Configuring proxy settings..."

# System-wide proxy
cat > /etc/environment << PROXYEOF
# Podman Security - Proxy Configuration
# Generated: $(date)
HTTP_PROXY=${PROXY_URL}
HTTPS_PROXY=${PROXY_URL}
http_proxy=${PROXY_URL}
https_proxy=${PROXY_URL}
NO_PROXY=localhost,127.0.0.1,.internal.company.com,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
no_proxy=localhost,127.0.0.1,.internal.company.com,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
PROXYEOF

# DNF proxy configuration
if [ -f /etc/dnf/dnf.conf ]; then
    if ! grep -q "^proxy=" /etc/dnf/dnf.conf; then
        echo "proxy=${PROXY_URL}" >> /etc/dnf/dnf.conf
    fi
fi

# Podman-specific proxy (user-level)
PRIMARY_USER=$(getent passwd 1000 | cut -d: -f1)
if [ -n "$PRIMARY_USER" ]; then
    USER_HOME=$(getent passwd $PRIMARY_USER | cut -d: -f6)
    mkdir -p "$USER_HOME/.config/containers"
    cat > "$USER_HOME/.config/containers/containers.conf" << PODPROXYEOF
[engine]
env = [
    "HTTP_PROXY=${PROXY_URL}",
    "HTTPS_PROXY=${PROXY_URL}",
    "NO_PROXY=localhost,127.0.0.1,.internal.company.com"
]
PODPROXYEOF
    chown -R ${PRIMARY_USER}:${PRIMARY_USER} "${USER_HOME}/.config/containers"
fi

echo "Proxy configuration complete"
