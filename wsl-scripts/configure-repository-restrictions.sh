#!/bin/bash
# Podman Security - Repository Restrictions Configuration
# This script configures system to only use internal mirrors for package updates

set -e

MIRROR_URL="{{MIRROR_URL}}"

echo "Configuring repository restrictions..."

# Backup and disable existing repos
mkdir -p /etc/yum.repos.d/disabled
for repo in /etc/yum.repos.d/*.repo; do
    if [ -f "$repo" ] && [ "$(basename $repo)" != "internal-mirror.repo" ]; then
        mv "$repo" /etc/yum.repos.d/disabled/ 2>/dev/null || true
    fi
done

# Create internal mirror repository configuration
cat > /etc/yum.repos.d/internal-mirror.repo << REPOEOF
# Podman Security - Internal Mirror Configuration
# Generated: $(date)
# DO NOT MODIFY - Managed by Podman Security Setup

[internal-fedora-base]
name=Internal Fedora Base Mirror
baseurl=\${MIRROR_URL}/fedora/\$releasever/Everything/\$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch
metadata_expire=7d
skip_if_unavailable=False

[internal-fedora-updates]
name=Internal Fedora Updates Mirror
baseurl=\${MIRROR_URL}/fedora/updates/\$releasever/Everything/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch
metadata_expire=1d
skip_if_unavailable=False
REPOEOF

# Replace MIRROR_URL placeholder
sed -i "s|\${MIRROR_URL}|${MIRROR_URL}|g" /etc/yum.repos.d/internal-mirror.repo

# Lock down DNF configuration
cat > /etc/dnf/dnf.conf << DNFEOF
[main]
gpgcheck=1
installonly_limit=3
clean_requirements_on_remove=True
best=False
skip_if_unavailable=False

# Security: Only allow configured repos
repo_gpgcheck=1
localpkg_gpgcheck=1
DNFEOF

echo "Repository configuration complete"
echo "Enabled repositories:"
dnf repolist enabled 2>/dev/null || true
