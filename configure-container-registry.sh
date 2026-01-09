#!/bin/bash
# Podman Security - Container Registry Restrictions Configuration
# This script configures Podman to only use internal container registry

set -e

INTERNAL_REGISTRY="{{INTERNAL_REGISTRY}}"

echo "Configuring container registry restrictions..."

# Create containers directory if it doesn't exist
mkdir -p /etc/containers

# Create registries.conf
cat > /etc/containers/registries.conf << 'REGEOF'
# Podman Security - Registry Configuration
# Generated: $(date)
# DO NOT MODIFY - Managed by Podman Security Setup

# ===========================================
# Only allow internal registry
# ===========================================
unqualified-search-registries = ["INTERNAL_REGISTRY_PLACEHOLDER"]

# ===========================================
# Block all public registries
# ===========================================
[[registry]]
location = "docker.io"
blocked = true

[[registry]]
location = "quay.io"
blocked = true

[[registry]]
location = "gcr.io"
blocked = true

[[registry]]
location = "ghcr.io"
blocked = true

[[registry]]
location = "registry.k8s.io"
blocked = true

[[registry]]
location = "mcr.microsoft.com"
blocked = true

# ===========================================
# Internal registry configuration
# ===========================================
[[registry]]
location = "INTERNAL_REGISTRY_PLACEHOLDER"
insecure = false
REGEOF

# Replace placeholder with actual registry
sed -i "s|INTERNAL_REGISTRY_PLACEHOLDER|${INTERNAL_REGISTRY}|g" /etc/containers/registries.conf

# Create policy.json for image signing
cat > /etc/containers/policy.json << 'POLICYEOF'
{
    "default": [
        {
            "type": "reject"
        }
    ],
    "transports": {
        "docker": {
            "INTERNAL_REGISTRY_PLACEHOLDER": [
                {
                    "type": "insecureAcceptAnything"
                }
            ]
        },
        "docker-daemon": {
            "": [
                {
                    "type": "insecureAcceptAnything"
                }
            ]
        }
    }
}
POLICYEOF

# Replace placeholder
sed -i "s|INTERNAL_REGISTRY_PLACEHOLDER|${INTERNAL_REGISTRY}|g" /etc/containers/policy.json

echo "Container registry configuration complete"
