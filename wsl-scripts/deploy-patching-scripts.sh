#!/bin/bash
# Podman Security - Deploy Patching Scripts
# This script deploys update and health check scripts for Podman security

set -e

echo "Deploying patching scripts..."

# Create scripts directory
mkdir -p /opt/podman-security/scripts
mkdir -p /var/log/podman-updates

# Create system update script
cat > /opt/podman-security/scripts/update-system.sh << 'UPDATEEOF'
#!/bin/bash
# Podman Security - System Update Script
# Run monthly or as needed for security updates

set -euo pipefail

LOG_DIR="/var/log/podman-updates"
LOG_FILE="$LOG_DIR/system-update-$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "Starting system update"
log "=========================================="

# Check current versions
log "Current package versions:"
rpm -qa podman buildah skopeo 2>/dev/null | tee -a "$LOG_FILE" || true

# Check for updates
log "Checking for available updates..."
dnf check-update 2>&1 | tee -a "$LOG_FILE" || true

# Apply security updates
log "Applying security updates..."
dnf update --security -y 2>&1 | tee -a "$LOG_FILE"

# Update container tools specifically
log "Updating container tools..."
dnf update podman buildah skopeo containers-common -y 2>&1 | tee -a "$LOG_FILE" || true

# Clean up
log "Cleaning package cache..."
dnf clean all 2>&1 | tee -a "$LOG_FILE"

# Log new versions
log "Updated package versions:"
rpm -qa podman buildah skopeo 2>/dev/null | tee -a "$LOG_FILE" || true

log "=========================================="
log "System update completed successfully"
log "=========================================="
UPDATEEOF

# Create image update script
cat > /opt/podman-security/scripts/update-images.sh << 'IMAGEEOF'
#!/bin/bash
# Podman Security - Container Image Update Script

set -euo pipefail

LOG_DIR="/var/log/podman-updates"
LOG_FILE="$LOG_DIR/image-update-$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "Starting container image update"
log "=========================================="

# Get list of local images from internal registry only
IMAGES=$(podman images --format "{{.Repository}}:{{.Tag}}" | grep -v "^<none>" || true)

if [ -z "$IMAGES" ]; then
    log "No images found to update"
    exit 0
fi

for IMAGE in $IMAGES; do
    log "Pulling latest: $IMAGE"
    podman pull "$IMAGE" 2>&1 | tee -a "$LOG_FILE" || {
        log "WARNING: Failed to pull $IMAGE"
    }
done

# Prune old images
log "Pruning unused images..."
podman image prune -f 2>&1 | tee -a "$LOG_FILE"

log "=========================================="
log "Image update completed"
log "=========================================="
IMAGEEOF

# Create health check script
cat > /opt/podman-security/scripts/health-check.sh << 'HEALTHEOF'
#!/bin/bash
# Podman Security - Health Check Script

echo "========================================"
echo "Podman Security Health Check"
echo "Date: $(date)"
echo "========================================"

echo ""
echo "--- Podman Status ---"
podman info 2>/dev/null | grep -E "(rootless|version)" || echo "Podman not running"

echo ""
echo "--- SSH Binding ---"
ss -tlnp 2>/dev/null | grep ssh || netstat -tlnp 2>/dev/null | grep ssh || echo "SSH not found"

echo ""
echo "--- Enabled Repositories ---"
dnf repolist enabled 2>/dev/null || echo "DNF not available"

echo ""
echo "--- Firewall Status ---"
firewall-cmd --state 2>/dev/null || echo "Firewalld not running"
firewall-cmd --get-default-zone 2>/dev/null || true

echo ""
echo "--- SELinux Status ---"
getenforce 2>/dev/null || echo "SELinux not available"

echo ""
echo "--- Container Registry Config ---"
grep -E "^(unqualified|blocked)" /etc/containers/registries.conf 2>/dev/null | head -10 || echo "Config not found"

echo ""
echo "--- DNS Configuration ---"
cat /etc/resolv.conf 2>/dev/null | grep -v "^#" || echo "resolv.conf not found"

echo ""
echo "========================================"
echo "Health check complete"
echo "========================================"
HEALTHEOF

# Set permissions
chmod +x /opt/podman-security/scripts/*.sh

# Create systemd timer for monthly updates (optional)
cat > /etc/systemd/system/podman-security-update.service << 'SVCEOF'
[Unit]
Description=Podman Security Monthly Update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/podman-security/scripts/update-system.sh
StandardOutput=journal
StandardError=journal
SVCEOF

cat > /etc/systemd/system/podman-security-update.timer << 'TIMEREOF'
[Unit]
Description=Monthly Podman Security Update

[Timer]
OnCalendar=Sat *-*-8..14 02:00:00
Persistent=true
RandomizedDelaySec=1800

[Install]
WantedBy=timers.target
TIMEREOF

# Reload systemd but don't enable timer by default
systemctl daemon-reload 2>/dev/null || true

echo "Patching scripts deployed to /opt/podman-security/scripts/"
echo "Available scripts:"
ls -la /opt/podman-security/scripts/
