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

# Import common module
Import-Module (Join-Path $PSScriptRoot "PodmanSecurityCommon.psm1") -Force

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

# Convert backup path for WSL
$wslBackupPath = wsl -d $WslDistro -- wslpath -u ($wslBackupDir -replace '\\', '/')

# Create logging scriptblock for the common module
$logScriptBlock = {
    param($Message, $Level)
    Write-Log -Message $Message -Level $Level
}

try {
    Invoke-ExternalBashScript `
        -ScriptName "backup-wsl.sh" `
        -WslDistro $WslDistro `
        -Description "WSL Configuration Backup" `
        -Variables @{ BACKUP_DIR = $wslBackupPath } `
        -ScriptRoot $PSScriptRoot `
        -LogFunction $logScriptBlock
} catch {
    Write-Log "WSL backup script returned warnings: $_" -Level WARN
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
