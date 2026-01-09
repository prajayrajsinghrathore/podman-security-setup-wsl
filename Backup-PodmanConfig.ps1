<#
.SYNOPSIS
    Podman Security WSL Backup Script
    
.DESCRIPTION
    Creates a backup of all WSL configurations that would be modified
    by the Podman security setup. Can be run independently before
    making manual changes or as part of a backup strategy.
    
.PARAMETER WslDistro
    Name of the WSL distribution to backup (default: podman-machine-default)
    
.PARAMETER BackupPath
    Path to store backups (default: C:\PodmanSecurityBackup)
    
.PARAMETER IncludeWindows
    Also backup Windows configurations (.wslconfig, firewall rules)
    
.EXAMPLE
    .\Backup-PodmanConfig.ps1
    
.EXAMPLE
    .\Backup-PodmanConfig.ps1 -WslDistro "my-podman" -BackupPath "D:\Backups" -IncludeWindows
    
.OUTPUTS
    Returns the path to the created backup directory
    
.NOTES
    Author: Infrastructure/Security Engineering
    Version: 1.0
#>

[CmdletBinding()]
param(
    [string]$WslDistro = "podman-machine-default",
    [string]$BackupPath = "C:\PodmanSecurityBackup",
    [switch]$IncludeWindows
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "INFO"    { Write-Host $logMessage -ForegroundColor Cyan }
        "WARN"    { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        "DEBUG"   { Write-Host $logMessage -ForegroundColor Gray }
    }
}

function Write-Banner {
    param([string]$Text)
    $border = "=" * 60
    Write-Host ""
    Write-Host $border -ForegroundColor Magenta
    Write-Host "  $Text" -ForegroundColor Magenta
    Write-Host $border -ForegroundColor Magenta
    Write-Host ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Banner "Podman Configuration Backup"

# Validate WSL distribution exists
$distros = wsl --list --quiet 2>&1
if ($distros -notcontains $WslDistro) {
    Write-Log "WSL distribution '$WslDistro' not found" -Level ERROR
    Write-Log "Available distributions:" -Level INFO
    wsl --list --verbose
    exit 1
}

# Create timestamped backup directory
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $BackupPath $timestamp

Write-Log "Creating backup directory: $backupDir"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

# Create subdirectories
$wslBackupDir = Join-Path $backupDir "wsl"
New-Item -ItemType Directory -Path $wslBackupDir -Force | Out-Null

# ============================================================================
# WINDOWS BACKUP
# ============================================================================

if ($IncludeWindows) {
    Write-Banner "Backing Up Windows Configuration"
    
    $windowsBackupDir = Join-Path $backupDir "windows"
    New-Item -ItemType Directory -Path $windowsBackupDir -Force | Out-Null
    
    # Backup .wslconfig
    $wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
    if (Test-Path $wslConfigPath) {
        Write-Log "Backing up .wslconfig"
        Copy-Item $wslConfigPath (Join-Path $windowsBackupDir ".wslconfig.backup")
        Write-Log ".wslconfig backed up" -Level SUCCESS
    } else {
        Write-Log ".wslconfig does not exist (skipping)" -Level DEBUG
    }
    
    # Export firewall rules
    Write-Log "Backing up Windows Firewall rules"
    $firewallRules = Get-NetFirewallRule -DisplayName "*WSL*" -ErrorAction SilentlyContinue
    if ($firewallRules) {
        $firewallRules | Export-Clixml (Join-Path $windowsBackupDir "firewall-rules.xml")
        Write-Log "Firewall rules backed up ($($firewallRules.Count) rules)" -Level SUCCESS
    } else {
        Write-Log "No WSL firewall rules found (skipping)" -Level DEBUG
    }
    
    # Export Podman-specific rules
    $podmanRules = Get-NetFirewallRule -DisplayName "Podman-*" -ErrorAction SilentlyContinue
    if ($podmanRules) {
        $podmanRules | Export-Clixml (Join-Path $windowsBackupDir "podman-firewall-rules.xml")
        Write-Log "Podman firewall rules backed up ($($podmanRules.Count) rules)" -Level SUCCESS
    }
}

# ============================================================================
# WSL BACKUP
# ============================================================================

Write-Banner "Backing Up WSL Configuration"

$backupScript = @'
#!/bin/bash
set -e

BACKUP_DIR="$1"

echo "Creating backup directories..."
mkdir -p "$BACKUP_DIR/containers"
mkdir -p "$BACKUP_DIR/yum.repos.d"

echo ""
echo "=== SSH Configuration ==="
if [ -f /etc/ssh/sshd_config ]; then
    cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.backup"
    echo "Backed up: /etc/ssh/sshd_config"
else
    echo "Not found: /etc/ssh/sshd_config (skipping)"
fi

echo ""
echo "=== Repository Configuration ==="
if [ -d /etc/yum.repos.d ]; then
    cp /etc/yum.repos.d/*.repo "$BACKUP_DIR/yum.repos.d/" 2>/dev/null || echo "No .repo files found"
    echo "Backed up: /etc/yum.repos.d/*.repo"
fi

echo ""
echo "=== Container Configuration ==="
if [ -f /etc/containers/registries.conf ]; then
    cp /etc/containers/registries.conf "$BACKUP_DIR/containers/"
    echo "Backed up: /etc/containers/registries.conf"
fi

if [ -f /etc/containers/containers.conf ]; then
    cp /etc/containers/containers.conf "$BACKUP_DIR/containers/"
    echo "Backed up: /etc/containers/containers.conf"
fi

if [ -f /etc/containers/policy.json ]; then
    cp /etc/containers/policy.json "$BACKUP_DIR/containers/"
    echo "Backed up: /etc/containers/policy.json"
fi

echo ""
echo "=== DNS Configuration ==="
if [ -f /etc/resolv.conf ]; then
    # Remove immutable flag temporarily if set
    chattr -i /etc/resolv.conf 2>/dev/null || true
    cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf.backup"
    echo "Backed up: /etc/resolv.conf"
fi

echo ""
echo "=== User Namespace Configuration ==="
if [ -f /etc/subuid ]; then
    cp /etc/subuid "$BACKUP_DIR/subuid.backup"
    echo "Backed up: /etc/subuid"
fi

if [ -f /etc/subgid ]; then
    cp /etc/subgid "$BACKUP_DIR/subgid.backup"
    echo "Backed up: /etc/subgid"
fi

echo ""
echo "=== Firewall Configuration ==="
if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --list-all > "$BACKUP_DIR/firewall-config.txt" 2>/dev/null || echo "Could not export firewall config"
    firewall-cmd --get-default-zone > "$BACKUP_DIR/firewall-zone.txt" 2>/dev/null || true
    echo "Backed up: firewall configuration"
else
    echo "Firewalld not installed (skipping)"
fi

echo ""
echo "=== Environment Configuration ==="
if [ -f /etc/environment ]; then
    cp /etc/environment "$BACKUP_DIR/environment.backup"
    echo "Backed up: /etc/environment"
fi

if [ -f /etc/dnf/dnf.conf ]; then
    cp /etc/dnf/dnf.conf "$BACKUP_DIR/dnf.conf.backup"
    echo "Backed up: /etc/dnf/dnf.conf"
fi

echo ""
echo "=== Backup Manifest ==="
echo "Backup completed at: $(date)" > "$BACKUP_DIR/manifest.txt"
echo "Files backed up:" >> "$BACKUP_DIR/manifest.txt"
find "$BACKUP_DIR" -type f -name "*.backup" -o -name "*.txt" -o -name "*.conf" -o -name "*.repo" 2>/dev/null | sort >> "$BACKUP_DIR/manifest.txt"

echo ""
echo "WSL backup complete!"
'@

Write-Log "Executing WSL backup script..."

try {
    $tempScript = [System.IO.Path]::GetTempFileName()
    $backupScript | Out-File -FilePath $tempScript -Encoding utf8 -NoNewline
    
    # Convert paths for WSL
    $wslBackupPath = wsl -d $WslDistro -- wslpath -u ($wslBackupDir -replace '\\', '/')
    $wslScriptPath = wsl -d $WslDistro -- wslpath -u ($tempScript -replace '\\', '/')
    
    # Execute backup script
    wsl -d $WslDistro -- bash -c "sed -i 's/\r$//' '$wslScriptPath' && chmod +x '$wslScriptPath' && sudo bash '$wslScriptPath' '$wslBackupPath'"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "WSL backup script returned warnings" -Level WARN
    }
} finally {
    Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# SAVE METADATA
# ============================================================================

$metadata = @{
    Timestamp = $timestamp
    WslDistro = $WslDistro
    IncludesWindows = $IncludeWindows.IsPresent
    CreatedBy = $env:USERNAME
    ComputerName = $env:COMPUTERNAME
}

$metadata | ConvertTo-Json | Out-File (Join-Path $backupDir "backup-metadata.json")

# ============================================================================
# SUMMARY
# ============================================================================

Write-Banner "Backup Complete"

Write-Log "Backup location: $backupDir" -Level SUCCESS
Write-Log ""
Write-Log "Contents:" -Level INFO

# List backup contents
Get-ChildItem -Path $backupDir -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Substring($backupDir.Length + 1)
    Write-Log "  $relativePath" -Level DEBUG
}

Write-Log ""
Write-Log "To restore from this backup, use:" -Level INFO
Write-Log "  .\Rollback-PodmanSecurity.ps1 -BackupPath `"$backupDir`"" -Level INFO

# Return the backup path
return $backupDir
