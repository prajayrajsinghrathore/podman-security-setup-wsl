#!/bin/bash
# Podman Security - WSL Configuration Restore Script
# Restores WSL/Linux configurations from backup

set -e

BACKUP_DIR="{{BACKUP_DIR}}"

if [ -z "$BACKUP_DIR" ]; then
    echo "Error: Backup directory not specified"
    exit 1
fi

echo "WSL Backup directory: $BACKUP_DIR"

# Function to restore file
restore_file() {
    local src="$1"
    local dest="$2"
    if [ -f "$src" ]; then
        echo "Restoring $dest from $src"
        sudo cp "$src" "$dest"
        return 0
    else
        echo "Backup not found: $src"
        return 1
    fi
}

echo ""
echo "=== Restoring SSH Configuration ==="
if restore_file "$BACKUP_DIR/sshd_config.backup" "/etc/ssh/sshd_config"; then
    sudo systemctl restart sshd 2>/dev/null || sudo service sshd restart 2>/dev/null || true
    echo "SSH configuration restored and service restarted"
fi

echo ""
echo "=== Restoring Repository Configuration ==="
if [ -d "$BACKUP_DIR/yum.repos.d" ]; then
    # Remove the internal-mirror.repo
    sudo rm -f /etc/yum.repos.d/internal-mirror.repo

    # Restore original repos
    if [ -d /etc/yum.repos.d/disabled ]; then
        sudo mv /etc/yum.repos.d/disabled/*.repo /etc/yum.repos.d/ 2>/dev/null || true
        sudo rmdir /etc/yum.repos.d/disabled 2>/dev/null || true
    fi

    # Copy backed up repos
    sudo cp $BACKUP_DIR/yum.repos.d/*.repo /etc/yum.repos.d/ 2>/dev/null || true
    echo "Repository configuration restored"
fi

echo ""
echo "=== Restoring Container Configuration ==="
if [ -d "$BACKUP_DIR/containers" ]; then
    [ -f "$BACKUP_DIR/containers/registries.conf" ] && sudo cp "$BACKUP_DIR/containers/registries.conf" /etc/containers/
    [ -f "$BACKUP_DIR/containers/containers.conf" ] && sudo cp "$BACKUP_DIR/containers/containers.conf" /etc/containers/
    [ -f "$BACKUP_DIR/containers/policy.json" ] && sudo cp "$BACKUP_DIR/containers/policy.json" /etc/containers/
    echo "Container configuration restored"
else
    # Reset to defaults if no backup
    echo "No container config backup - resetting to defaults..."
    sudo rm -f /etc/containers/registries.conf /etc/containers/containers.conf
fi

echo ""
echo "=== Restoring DNS Configuration ==="
sudo chattr -i /etc/resolv.conf 2>/dev/null || true
if restore_file "$BACKUP_DIR/resolv.conf.backup" "/etc/resolv.conf"; then
    echo "DNS configuration restored"
else
    # Let WSL regenerate resolv.conf
    echo "No DNS backup - WSL will regenerate resolv.conf"
fi

echo ""
echo "=== Restoring Firewall Configuration ==="
if command -v firewall-cmd &>/dev/null; then
    sudo firewall-cmd --set-default-zone=public 2>/dev/null || true
    sudo firewall-cmd --permanent --zone=trusted --remove-source=127.0.0.0/8 2>/dev/null || true
    sudo firewall-cmd --permanent --zone=trusted --remove-source=10.0.0.0/8 2>/dev/null || true
    sudo firewall-cmd --permanent --zone=trusted --remove-source=172.16.0.0/12 2>/dev/null || true
    sudo firewall-cmd --permanent --zone=trusted --remove-source=192.168.0.0/16 2>/dev/null || true
    sudo firewall-cmd --reload 2>/dev/null || true
    echo "Firewall reset to default zone: public"
fi

echo ""
echo "=== Restoring User Namespace Configuration ==="
restore_file "$BACKUP_DIR/subuid.backup" "/etc/subuid" || true
restore_file "$BACKUP_DIR/subgid.backup" "/etc/subgid" || true

echo ""
echo "=== Removing Patching Scripts ==="
if [ -d /opt/podman-security ]; then
    sudo rm -rf /opt/podman-security
    echo "Removed /opt/podman-security"
fi

# Remove systemd timers
sudo systemctl disable podman-security-update.timer 2>/dev/null || true
sudo rm -f /etc/systemd/system/podman-security-update.* 2>/dev/null || true
sudo systemctl daemon-reload 2>/dev/null || true

echo ""
echo "=== Restoring Proxy Configuration ==="
# Remove proxy settings from environment
sudo sed -i '/HTTP_PROXY\|HTTPS_PROXY\|NO_PROXY\|http_proxy\|https_proxy\|no_proxy/d' /etc/environment 2>/dev/null || true

# Remove proxy from DNF config
sudo sed -i '/^proxy=/d' /etc/dnf/dnf.conf 2>/dev/null || true

echo ""
echo "=========================================="
echo "WSL Rollback Complete"
echo "=========================================="
