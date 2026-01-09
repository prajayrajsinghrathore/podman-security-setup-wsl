# Podman Enterprise Security Setup

## Overview

This modular script system configures a secure Podman environment on Windows with WSL2.

## Features

- **Idempotent**: Safe to run multiple times without side effects
- **Modular Design**: Separate scripts for setup, backup, verification, and rollback
- **Backup & Rollback**: All configurations are backed up; full rollback script provided
- **Prerequisite Checks**: Validates environment before making changes
- **Dry Run Mode**: Preview changes without applying them
- **Comprehensive Logging**: All actions logged for audit trail

## Scripts Included

| Script | Purpose |
|--------|---------|
| `Setup-PodmanSecurity.ps1` | Main orchestrator - configures all security settings |
| `Rollback-PodmanSecurity.ps1` | Restores system from backup |
| `Test-PodmanSecurity.ps1` | Verifies security configuration (can run independently) |
| `Backup-PodmanConfig.ps1` | Creates configuration backups (can run independently) |
| `config-template.json` | Configuration template for customization |

## Quick Start

### Basic Usage

```powershell
# Run as Administrator
.\Setup-PodmanSecurity.ps1
```

### Dry Run (Preview Changes)

```powershell
.\Setup-PodmanSecurity.ps1 -DryRun
```

### Custom Configuration

```powershell
.\Setup-PodmanSecurity.ps1 `
    -WslDistro "podman-machine-default" `
    -InternalMirrorUrl "https://repo.mycompany.com" `
    -InternalRegistryUrl "registry.mycompany.com" `
    -InternalDnsServer "10.1.1.10" `
    -InternalProxyUrl "http://proxy.mycompany.com:8080"
```

## Modular Usage

### Run Verification Independently

```powershell
# Check security posture at any time
.\Test-PodmanSecurity.ps1 -WslDistro "podman-machine-default"

# Detailed output
.\Test-PodmanSecurity.ps1 -Detailed
```

### Create Backup Independently

```powershell
# Backup WSL configurations only
.\Backup-PodmanConfig.ps1 -WslDistro "podman-machine-default"

# Include Windows configurations
.\Backup-PodmanConfig.ps1 -IncludeWindows -BackupPath "D:\Backups"
```

### Rollback from Backup

```powershell
.\Rollback-PodmanSecurity.ps1 -BackupPath "C:\PodmanSecurityBackup\20240115_143022"
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-WslDistro` | WSL distribution name | `podman-machine-default` |
| `-InternalMirrorUrl` | Internal Fedora mirror URL | `https://mirror.internal.company.com` |
| `-InternalRegistryUrl` | Internal container registry | `registry.internal.company.com` |
| `-InternalDnsServer` | Internal DNS server IP | `10.0.0.10` |
| `-InternalProxyUrl` | Internal proxy server URL | `http://proxy.internal.company.com:8080` |
| `-BackupPath` | Backup storage location | `C:\PodmanSecurityBackup` |
| `-SkipPrerequisiteCheck` | Bypass prerequisite validation | `false` |
| `-DryRun` | Preview mode (no changes) | `false` |

## What Gets Configured

### Windows Configuration

1. **WSL Settings** (`.wslconfig`)
   - Memory and CPU limits
   - Mirrored networking mode
   - Localhost forwarding only
   - GUI applications disabled

2. **Windows Firewall**
   - Block all WSL outbound traffic by default
   - Allow internal network ranges (10.x, 172.16.x, 192.168.x)
   - Allow localhost communication
   - Block all inbound to WSL

### Linux/WSL Configuration

1. **SSH Security** (`/etc/ssh/sshd_config`)
   - Bind to 127.0.0.1 and ::1 only
   - Disable root login
   - Key-based authentication only
   - Disable forwarding features
   - Connection rate limiting

2. **Repository Restrictions**
   - Disable all public Fedora repositories
   - Configure internal mirror only
   - Enable GPG verification

3. **Container Registry**
   - Block docker.io, quay.io, gcr.io, ghcr.io
   - Allow only internal registry
   - Configure image signing policy

4. **Rootless Mode**
   - Configure subuid/subgid mappings
   - Restrict default capabilities
   - Enable SELinux enforcement
   - Disable privileged containers

5. **Linux Firewall**
   - Default zone set to `drop`
   - Allow only localhost and internal networks
   - Allow internal DNS server

6. **DNS Configuration**
   - Point to internal DNS only
   - Make resolv.conf immutable

7. **Proxy Configuration**
   - System-wide proxy settings
   - DNF proxy configuration
   - Podman-specific proxy settings

## Directory Structure

After running the setup, the following structure is created:

```
C:\PodmanSecurityBackup\
└── 20240115_143022\              # Timestamped backup folder
    ├── config.json               # Setup configuration
    ├── setup.log                 # Execution log
    ├── Rollback-PodmanSecurity.ps1  # Rollback script
    ├── windows\
    │   ├── .wslconfig.backup     # Original WSL config
    │   └── firewall-rules.xml    # Original firewall rules
    └── wsl\
        ├── sshd_config.backup    # Original SSH config
        ├── yum.repos.d\          # Original repository configs
        ├── containers\           # Original container configs
        ├── resolv.conf.backup    # Original DNS config
        └── firewall-config.txt   # Original firewall state

/opt/podman-security/             # (Inside WSL)
└── scripts/
    ├── update-system.sh          # Monthly system update script
    ├── update-images.sh          # Container image update script
    └── health-check.sh           # Configuration health check
```

## Rollback

To restore the system to its previous state:

```powershell
.\Rollback-PodmanSecurity.ps1 -BackupPath "C:\PodmanSecurityBackup\20240115_143022"
```

### Rollback Options

```powershell
# Restore everything
.\Rollback-PodmanSecurity.ps1 -BackupPath "..." -RestoreAll

# Restore only Windows configurations
.\Rollback-PodmanSecurity.ps1 -BackupPath "..." -RestoreWindowsOnly

# Restore only WSL configurations
.\Rollback-PodmanSecurity.ps1 -BackupPath "..." -RestoreWslOnly
```

## Post-Installation

### Verify Configuration

```powershell
# Run health check
wsl -d podman-machine-default -- /opt/podman-security/scripts/health-check.sh
```

### Test Podman

```powershell
# Check Podman status
wsl -d podman-machine-default -- podman info

# Verify rootless mode
wsl -d podman-machine-default -- podman info | grep -i rootless

# Test that public registries are blocked
wsl -d podman-machine-default -- podman pull docker.io/library/alpine
# Expected: Error - registry blocked
```

### Manual Patching

```bash
# System updates
sudo /opt/podman-security/scripts/update-system.sh

# Container image updates
/opt/podman-security/scripts/update-images.sh
```

### Enable Automatic Patching (Optional)

```bash
# Enable monthly update timer
sudo systemctl enable --now podman-security-update.timer

# Check timer status
systemctl list-timers | grep podman
```

## Troubleshooting

### Prerequisites Failed

```powershell
# Check WSL version
wsl --version

# List available distributions
wsl --list --verbose

# Update WSL
wsl --update
```

### SSH Still Accessible from Network

```bash
# Verify SSH binding
ss -tlnp | grep ssh
# Should show: 127.0.0.1:22 only

# Restart SSH
sudo systemctl restart sshd
```

### Cannot Pull Images

```bash
# Check registry configuration
cat /etc/containers/registries.conf

# Verify internal registry is accessible
curl -k https://registry.internal.company.com/v2/
```

### Firewall Issues

```bash
# Check firewall status
sudo firewall-cmd --state
sudo firewall-cmd --list-all

# Temporarily disable for testing
sudo systemctl stop firewalld
```

## Security Considerations

1. **Keep backups secure**: The backup directory contains sensitive configuration data
2. **Verify internal services**: Ensure your internal mirror and registry are operational before running
3. **Test in non-production**: Always test in a development environment first
4. **Review logs**: Check setup.log for any warnings or errors
5. **Regular health checks**: Schedule periodic runs of the health-check script

## Compliance Checklist

After running the setup, verify:

- [ ] SSH binds to localhost only (`ss -tlnp | grep ssh`)
- [ ] Rootless mode enabled (`podman info | grep rootless`)
- [ ] Public repos disabled (`dnf repolist`)
- [ ] Public registries blocked (`podman pull docker.io/alpine` fails)
- [ ] Firewall active and default zone is drop
- [ ] SELinux enforcing (`getenforce`)
- [ ] DNS points to internal server (`cat /etc/resolv.conf`)
- [ ] Patching scripts deployed (`ls /opt/podman-security/scripts/`)

## Support

For issues or questions:
1. Review the setup.log in the backup directory
2. Run the health-check script for diagnostic information
3. Contact Infrastructure/Security Engineering team

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-01-15 | Initial release |
