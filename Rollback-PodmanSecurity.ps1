<#
.SYNOPSIS
    Podman Security Rollback Script
    
.DESCRIPTION
    Restores the system to its state before Podman security configuration.
    Uses backups created during the setup process.
    
.PARAMETER BackupPath
    Path to the backup directory created during setup (required)
    
.PARAMETER RestoreAll
    Restore all configurations (default behavior)
    
.PARAMETER RestoreWindowsOnly
    Only restore Windows configurations (.wslconfig, firewall)
    
.PARAMETER RestoreWslOnly
    Only restore WSL/Linux configurations
    
.PARAMETER Force
    Skip confirmation prompts
    
.EXAMPLE
    .\Rollback-PodmanSecurity.ps1 -BackupPath "C:\PodmanSecurityBackup\20240115_143022"
    
.EXAMPLE
    .\Rollback-PodmanSecurity.ps1 -BackupPath "C:\PodmanSecurityBackup\20240115_143022" -RestoreWindowsOnly
    
.NOTES
    Author: Infrastructure/Security Engineering
    Version: 1.0
    Requires: Administrator privileges
#>

[CmdletBinding(DefaultParameterSetName = 'All')]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$BackupPath,
    
    [Parameter(ParameterSetName = 'All')]
    [switch]$RestoreAll,
    
    [Parameter(ParameterSetName = 'WindowsOnly')]
    [switch]$RestoreWindowsOnly,
    
    [Parameter(ParameterSetName = 'WslOnly')]
    [switch]$RestoreWslOnly,
    
    [switch]$Force
)

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import shared module
Import-Module (Join-Path $PSScriptRoot "PodmanSecurityCommon.psm1") -Force

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

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
    param([string]$Text, [string]$Color = "Red")
    $border = "=" * 60
    Write-Host ""
    Write-Host $border -ForegroundColor $Color
    Write-Host "  $Text" -ForegroundColor $Color
    Write-Host $border -ForegroundColor $Color
    Write-Host ""
}

# ============================================================================
# MAIN ROLLBACK FUNCTIONS
# ============================================================================

function Restore-WindowsConfiguration {
    param([string]$BackupDir)
    
    Write-Banner "Restoring Windows Configuration" -Color Yellow
    
    $windowsBackupDir = Join-Path $BackupDir "windows"
    
    # Restore .wslconfig
    $wslConfigBackup = Join-Path $windowsBackupDir ".wslconfig.backup"
    $wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
    
    if (Test-Path $wslConfigBackup) {
        Write-Log "Restoring .wslconfig from backup..."
        Copy-Item $wslConfigBackup $wslConfigPath -Force
        Write-Log ".wslconfig restored" -Level SUCCESS
    } else {
        Write-Log "No .wslconfig backup found - removing current config..."
        Remove-Item $wslConfigPath -Force -ErrorAction SilentlyContinue
        Write-Log ".wslconfig removed (no original existed)" -Level SUCCESS
    }
    
    # Remove Podman firewall rules
    Write-Log "Removing Podman security firewall rules..."
    $rules = Get-NetFirewallRule -DisplayName "Podman-*" -ErrorAction SilentlyContinue
    if ($rules) {
        $rules | Remove-NetFirewallRule
        Write-Log "Removed $($rules.Count) firewall rule(s)" -Level SUCCESS
    } else {
        Write-Log "No Podman firewall rules found" -Level DEBUG
    }
    
    # Restore original firewall rules if backup exists
    $firewallBackup = Join-Path $windowsBackupDir "firewall-rules.xml"
    if (Test-Path $firewallBackup) {
        Write-Log "Note: Original firewall rules backup exists at $firewallBackup" -Level INFO
        Write-Log "Manual review recommended before restoring firewall rules" -Level WARN
    }
    
    Write-Log "Windows configuration rollback complete" -Level SUCCESS
}

function Restore-WslConfiguration {
    param(
        [string]$BackupDir,
        [string]$WslDistro
    )

    Write-Banner "Restoring WSL Configuration" -Color Yellow

    $wslBackupDir = Join-Path $BackupDir "wsl"

    if (-not (Test-Path $wslBackupDir)) {
        Write-Log "WSL backup directory not found: $wslBackupDir" -Level ERROR
        return
    }

    Write-Log "Executing WSL rollback script..."

    # Convert WSL backup path for bash script
    $wslBackupPath = wsl -d $WslDistro -- wslpath -u ($wslBackupDir -replace '\\', '/')

    # Use the shared module to execute the external restore script
    Invoke-ExternalBashScript `
        -ScriptName "restore-wsl-config.sh" `
        -WslDistro $WslDistro `
        -Description "WSL Configuration Restore" `
        -Variables @{
            BACKUP_DIR = $wslBackupPath
        } `
        -ScriptRoot $PSScriptRoot `
        -UseSudo $true `
        -DryRun $false `
        -LogFunction ${function:Write-Log}

    if ($LASTEXITCODE -ne 0) {
        Write-Log "WSL rollback script returned non-zero exit code" -Level WARN
    }

    Write-Log "WSL configuration rollback complete" -Level SUCCESS
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Main {
    Write-Banner "PODMAN SECURITY ROLLBACK" -Color Red
    
    # Check for admin privileges
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "This script requires Administrator privileges" -Level ERROR
        throw "Please run as Administrator"
    }
    
    # Load configuration from backup
    $configFile = Join-Path $BackupPath "config.json"
    $config = $null
    $WslDistro = "podman-machine-default"  # Default
    
    if (Test-Path $configFile) {
        $config = Get-Content $configFile | ConvertFrom-Json
        Write-Log "Loaded configuration from: $configFile"
        if ($config.WslDistro) {
            $WslDistro = $config.WslDistro
        }
    } else {
        Write-Log "Configuration file not found - using defaults" -Level WARN
    }
    
    Write-Log "Backup path: $BackupPath"
    Write-Log "WSL Distribution: $WslDistro"
    Write-Log ""
    
    # Confirmation prompt
    if (-not $Force) {
        Write-Host ""
        Write-Host "WARNING: This will restore the system to its pre-configuration state." -ForegroundColor Yellow
        Write-Host "The following will be restored:" -ForegroundColor Yellow
        
        if (-not $RestoreWslOnly) {
            Write-Host "  - Windows .wslconfig" -ForegroundColor White
            Write-Host "  - Windows Firewall rules (Podman rules removed)" -ForegroundColor White
        }
        if (-not $RestoreWindowsOnly) {
            Write-Host "  - SSH configuration" -ForegroundColor White
            Write-Host "  - Repository configuration" -ForegroundColor White
            Write-Host "  - Container registry configuration" -ForegroundColor White
            Write-Host "  - Firewall configuration" -ForegroundColor White
            Write-Host "  - DNS configuration" -ForegroundColor White
            Write-Host "  - Proxy configuration" -ForegroundColor White
            Write-Host "  - Patching scripts (removed)" -ForegroundColor White
        }
        Write-Host ""
        
        $confirmation = Read-Host "Do you want to continue? (yes/no)"
        if ($confirmation -ne "yes") {
            Write-Log "Rollback cancelled by user"
            return
        }
    }
    
    try {
        # Restore Windows configurations
        if (-not $RestoreWslOnly) {
            Restore-WindowsConfiguration -BackupDir $BackupPath
        }
        
        # Restore WSL configurations
        if (-not $RestoreWindowsOnly) {
            Restore-WslConfiguration -BackupDir $BackupPath -WslDistro $WslDistro
        }
        
        # Restart WSL
        Write-Banner "Restarting WSL" -Color Yellow
        Write-Log "Shutting down WSL..."
        wsl --shutdown
        Start-Sleep -Seconds 3
        
        Write-Log "Starting WSL distribution..."
        wsl -d $WslDistro -- echo "WSL restarted successfully"
        
        Write-Banner "ROLLBACK COMPLETE" -Color Green
        Write-Log "System restored to pre-configuration state" -Level SUCCESS
        Write-Log ""
        Write-Log "Please verify:" -Level INFO
        Write-Log "  1. WSL is functioning: wsl -d $WslDistro" -Level INFO
        Write-Log "  2. Podman works: wsl -d $WslDistro -- podman info" -Level INFO
        Write-Log "  3. Network connectivity is restored" -Level INFO
        
    } catch {
        Write-Log "Rollback failed: $_" -Level ERROR
        Write-Log "Manual intervention may be required" -Level WARN
        throw
    }
}

# Run main function
Main
