<#
.SYNOPSIS
    Podman Enterprise Security Setup - Main Orchestrator Script
    
.DESCRIPTION
    This script sets up a secure Podman environment on Windows with WSL2.
    It configures network isolation, SSH security, repository restrictions,
    rootless mode, and controlled patching processes.
    
    The script is idempotent - safe to run multiple times.
    All changes are backed up before modification.
    
.PARAMETER WslDistro
    Name of the WSL distribution to configure (default: podman-machine-default)
    
.PARAMETER InternalMirrorUrl
    URL of the internal Fedora mirror (default: https://mirror.internal.company.com)
    
.PARAMETER InternalRegistryUrl
    URL of the internal container registry (default: registry.internal.company.com)
    
.PARAMETER InternalDnsServer
    IP address of internal DNS server (default: 10.0.0.10)
    
.PARAMETER InternalProxyUrl
    URL of internal proxy server (default: http://proxy.internal.company.com:8080)
    
.PARAMETER BackupPath
    Path to store backups (default: C:\PodmanSecurityBackup)
    
.PARAMETER SkipPrerequisiteCheck
    Skip prerequisite validation
    
.PARAMETER DryRun
    Show what would be done without making changes
    
.EXAMPLE
    .\Setup-PodmanSecurity.ps1 -DryRun
    
.EXAMPLE
    .\Setup-PodmanSecurity.ps1 -InternalMirrorUrl "https://repo.mycompany.com"
    
.NOTES
    Author: Infrastructure/Security Engineering
    Version: 1.0
    Requires: Windows 11 22H2+, WSL2, Administrator privileges
#>

[CmdletBinding()]
param(
    [string]$WslDistro = "podman-machine-default",
    [string]$InternalMirrorUrl = "https://mirror.internal.company.com",
    [string]$InternalRegistryUrl = "registry.internal.company.com",
    [string]$InternalDnsServer = "10.0.0.10",
    [string]$InternalProxyUrl = "http://proxy.internal.company.com:8080",
    [string]$BackupPath = "C:\PodmanSecurityBackup",
    [switch]$SkipPrerequisiteCheck,
    [switch]$DryRun
)

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import shared module
Import-Module (Join-Path $PSScriptRoot "PodmanSecurityCommon.psm1") -Force

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:Config = @{
    Version = "1.0.0"
    Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    LogFile = ""
    BackupDir = ""
    ScriptRoot = $PSScriptRoot
    WslDistro = $WslDistro
    InternalMirrorUrl = $InternalMirrorUrl
    InternalRegistryUrl = $InternalRegistryUrl
    InternalDnsServer = $InternalDnsServer
    InternalProxyUrl = $InternalProxyUrl
    DryRun = $DryRun
    # Bash script filenames
    BashScripts = @{
        SshSecurity = "configure-ssh-security.sh"
        RepositoryRestrictions = "configure-repository-restrictions.sh"
        ContainerRegistry = "configure-container-registry.sh"
        RootlessMode = "configure-rootless-mode.sh"
        LinuxFirewall = "configure-linux-firewall.sh"
        DnsConfiguration = "configure-dns.sh"
        ProxyConfiguration = "configure-proxy.sh"
        PatchingScripts = "deploy-patching-scripts.sh"
        Verification = "verify-configuration.sh"
        BackupWsl = "backup-wsl-config.sh"
        RestoreWsl = "restore-wsl-config.sh"
    }
    # Configuration template files (in config subfolder)
    Templates = @{
        WslConfig = "config\wslconfig.template"
    }
}

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
    
    if ($Script:Config.LogFile -and -not $DryRun) {
        Add-Content -Path $Script:Config.LogFile -Value $logMessage
    }
}

function Write-Banner {
    param([string]$Text)
    $border = "=" * 70
    Write-Host ""
    Write-Host $border -ForegroundColor Magenta
    Write-Host "  $Text" -ForegroundColor Magenta
    Write-Host $border -ForegroundColor Magenta
    Write-Host ""
}

# ============================================================================
# INITIALIZATION
# ============================================================================

function Initialize-Environment {
    Write-Banner "Podman Enterprise Security Setup v$($Script:Config.Version)"
    
    if ($DryRun) {
        Write-Log "DRY RUN MODE - No changes will be made" -Level WARN
    }
    
    # Create backup directory
    $Script:Config.BackupDir = Join-Path $BackupPath $Script:Config.Timestamp
    
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $Script:Config.BackupDir -Force | Out-Null
        $Script:Config.LogFile = Join-Path $Script:Config.BackupDir "setup.log"
        Write-Log "Backup directory created: $($Script:Config.BackupDir)"
    }
    
    # Export configuration for rollback
    if (-not $DryRun) {
        $Script:Config | ConvertTo-Json -Depth 10 | Out-File (Join-Path $Script:Config.BackupDir "config.json")
    }
}

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================

function Test-Prerequisites {
    Write-Banner "Checking Prerequisites"
    
    $checks = @{
        "Administrator Privileges" = $false
        "Windows Version" = $false
        "WSL2 Installed" = $false
        "WSL2 Version" = $false
        "Hyper-V Enabled" = $false
        "WSL Distribution Exists" = $false
    }
    
    # Check Administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $checks["Administrator Privileges"] = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    # Check Windows Version (Windows 11 22H2 or later preferred)
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $buildNumber = [int]$osInfo.BuildNumber
    $checks["Windows Version"] = $buildNumber -ge 22000  # Windows 11 minimum
    
    # Check WSL
    try {
        $wslVersion = wsl --version 2>&1
        $checks["WSL2 Installed"] = $LASTEXITCODE -eq 0
        $checks["WSL2 Version"] = $wslVersion -match "WSL.*(2|version)"
    } catch {
        $checks["WSL2 Installed"] = $false
    }
    
    # Check Hyper-V
    $hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
    $checks["Hyper-V Enabled"] = $hyperv.State -eq "Enabled"
    
    # Check WSL Distribution
    try {
        $distros = wsl --list --quiet 2>&1
        $checks["WSL Distribution Exists"] = $distros -contains $WslDistro
    } catch {
        $checks["WSL Distribution Exists"] = $false
    }
    
    # Report results
    $allPassed = $true
    foreach ($check in $checks.GetEnumerator()) {
        if ($check.Value) {
            Write-Log "$($check.Key): PASSED" -Level SUCCESS
        } else {
            Write-Log "$($check.Key): FAILED" -Level ERROR
            $allPassed = $false
        }
    }
    
    if (-not $allPassed) {
        Write-Log "Prerequisites check failed. Please resolve the issues above." -Level ERROR
        if (-not $checks["Administrator Privileges"]) {
            Write-Log "Run this script as Administrator" -Level WARN
        }
        if (-not $checks["WSL Distribution Exists"]) {
            Write-Log "WSL distribution '$WslDistro' not found. Available distributions:" -Level WARN
            wsl --list --verbose
        }
        
        if (-not $SkipPrerequisiteCheck) {
            throw "Prerequisites not met. Use -SkipPrerequisiteCheck to bypass (not recommended)."
        }
    }
    
    return $allPassed
}

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

function Invoke-Backup {
    Write-Banner "Backing Up Configurations"
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would backup configurations to $($Script:Config.BackupDir)" -Level DEBUG
        return
    }
    
    # Check if standalone backup script exists in same directory
    $backupScriptPath = Join-Path $PSScriptRoot "Backup-PodmanConfig.ps1"
    
    if (Test-Path $backupScriptPath) {
        Write-Log "Using standalone backup script: $backupScriptPath"
        $result = & $backupScriptPath -WslDistro $WslDistro -BackupPath $BackupPath -IncludeWindows
        $Script:Config.BackupDir = $result
    } else {
        # Fallback to inline backup if standalone script not found
        Write-Log "Standalone backup script not found, using inline backup" -Level DEBUG
        Invoke-InlineBackup
    }
    
    Write-Log "Backup complete: $($Script:Config.BackupDir)" -Level SUCCESS
}

function Invoke-InlineBackup {
    # Create backup directories
    $windowsBackupDir = Join-Path $Script:Config.BackupDir "windows"
    $wslBackupDir = Join-Path $Script:Config.BackupDir "wsl"

    New-Item -ItemType Directory -Path $windowsBackupDir -Force | Out-Null
    New-Item -ItemType Directory -Path $wslBackupDir -Force | Out-Null

    # Backup .wslconfig
    $wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
    if (Test-Path $wslConfigPath) {
        Write-Log "Backing up .wslconfig"
        Copy-Item $wslConfigPath (Join-Path $windowsBackupDir ".wslconfig.backup")
    }

    # Export current firewall rules
    Write-Log "Backing up Windows Firewall rules"
    $firewallRules = Get-NetFirewallRule -DisplayName "*WSL*" -ErrorAction SilentlyContinue
    if ($firewallRules) {
        $firewallRules | Export-Clixml (Join-Path $windowsBackupDir "firewall-rules.xml")
    }

    # Backup WSL configurations using external bash script
    Write-Log "Backing up WSL configurations..."

    # Convert WSL backup path for bash script
    $wslBackupPath = wsl -d $Script:Config.WslDistro -- wslpath -u ($wslBackupDir -replace '\\', '/')

    # Use Invoke-WslScript to execute the backup script with the backup directory as an argument
    $backupScriptPath = Join-Path $Script:Config.ScriptRoot (Join-Path "wsl-scripts" $Script:Config.BashScripts.BackupWsl)

    if (Test-Path $backupScriptPath) {
        $tempScript = [System.IO.Path]::GetTempFileName()
        Copy-Item $backupScriptPath $tempScript -Force

        try {
            $wslTempPath = wsl -d $Script:Config.WslDistro -- wslpath -u ($tempScript -replace '\\', '/')
            wsl -d $Script:Config.WslDistro -- bash -c "sed -i 's/\r$//' '$wslTempPath' && chmod +x '$wslTempPath' && sudo bash '$wslTempPath' '$wslBackupPath'"

            if ($LASTEXITCODE -ne 0) {
                throw "WSL backup script failed with exit code $LASTEXITCODE"
            }
        } finally {
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Log "Backup script not found: $backupScriptPath" -Level ERROR
        throw "Required backup script not found"
    }
}

# ============================================================================
# WINDOWS CONFIGURATION
# ============================================================================

function Set-WslConfig {
    Write-Banner "Configuring WSL Settings"

    $wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
    $templatePath = Join-Path $Script:Config.ScriptRoot $Script:Config.Templates.WslConfig

    # Check if template file exists
    if (-not (Test-Path $templatePath)) {
        Write-Log "WSL config template not found: $templatePath" -Level ERROR
        throw "Required template file not found"
    }

    # Read template and perform variable substitution
    $wslConfigContent = Get-Content $templatePath -Raw
    $wslConfigContent = $wslConfigContent -replace "\{\{TIMESTAMP\}\}", (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

    Write-Log "WSL configuration to be applied:"
    Write-Host $wslConfigContent -ForegroundColor Gray

    if (-not $DryRun) {
        $wslConfigContent | Out-File -FilePath $wslConfigPath -Encoding utf8 -Force
        Write-Log "WSL configuration written to $wslConfigPath" -Level SUCCESS
    } else {
        Write-Log "DRY RUN: Would write WSL config to $wslConfigPath" -Level DEBUG
    }
}

function Set-WindowsFirewall {
    Write-Banner "Configuring Windows Firewall"
    
    # Remove existing WSL rules (idempotent)
    Write-Log "Removing existing WSL firewall rules..."
    if (-not $DryRun) {
        Get-NetFirewallRule -DisplayName "Podman-*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    }
    
    # Block WSL outbound by default
    Write-Log "Creating firewall rule: Block WSL Outbound"
    if (-not $DryRun) {
        New-NetFirewallRule -DisplayName "Podman-Block-WSL-Outbound" `
            -Direction Outbound `
            -Action Block `
            -Program "%SystemRoot%\System32\wsl.exe" `
            -Enabled True `
            -Profile Any `
            -Description "Block all outbound traffic from WSL" | Out-Null
    }
    
    # Allow internal network ranges
    $internalRanges = @("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
    Write-Log "Creating firewall rule: Allow WSL to Internal Networks"
    if (-not $DryRun) {
        New-NetFirewallRule -DisplayName "Podman-Allow-WSL-Internal" `
            -Direction Outbound `
            -Action Allow `
            -Program "%SystemRoot%\System32\wsl.exe" `
            -RemoteAddress $internalRanges `
            -Enabled True `
            -Profile Any `
            -Description "Allow WSL to communicate with internal networks only" | Out-Null
    }
    
    # Allow localhost
    Write-Log "Creating firewall rule: Allow WSL Localhost"
    if (-not $DryRun) {
        New-NetFirewallRule -DisplayName "Podman-Allow-WSL-Localhost" `
            -Direction Outbound `
            -Action Allow `
            -Program "%SystemRoot%\System32\wsl.exe" `
            -RemoteAddress "127.0.0.0/8" `
            -Enabled True `
            -Profile Any `
            -Description "Allow WSL localhost communication" | Out-Null
    }
    
    # Block inbound to WSL
    Write-Log "Creating firewall rule: Block Inbound to WSL"
    if (-not $DryRun) {
        New-NetFirewallRule -DisplayName "Podman-Block-WSL-Inbound" `
            -Direction Inbound `
            -Action Block `
            -Program "%SystemRoot%\System32\wsl.exe" `
            -Enabled True `
            -Profile Any `
            -Description "Block all inbound traffic to WSL from external sources" | Out-Null
    }
    
    Write-Log "Windows Firewall configuration complete" -Level SUCCESS
}

# ============================================================================
# WSL/LINUX CONFIGURATION
# ============================================================================
# Note: Invoke-WslScript and Invoke-ExternalBashScript functions are now in PodmanSecurityCommon.psm1

function Set-SshSecurity {
    Write-Banner "Configuring SSH Security"

    Invoke-ExternalBashScript `
        -ScriptName $Script:Config.BashScripts.SshSecurity `
        -WslDistro $Script:Config.WslDistro `
        -Description "SSH Security Configuration" `
        -ScriptRoot $Script:Config.ScriptRoot `
        -DryRun $Script:Config.DryRun `
        -LogFunction ${function:Write-Log}

    Write-Log "SSH security configuration complete" -Level SUCCESS
}

function Set-RepositoryRestrictions {
    Write-Banner "Configuring Repository Restrictions"

    Invoke-ExternalBashScript `
        -ScriptName $Script:Config.BashScripts.RepositoryRestrictions `
        -WslDistro $Script:Config.WslDistro `
        -Description "Repository Restrictions Configuration" `
        -Variables @{
            MIRROR_URL = $Script:Config.InternalMirrorUrl
        } `
        -ScriptRoot $Script:Config.ScriptRoot `
        -DryRun $Script:Config.DryRun `
        -LogFunction ${function:Write-Log}

    Write-Log "Repository restrictions configuration complete" -Level SUCCESS
}

function Set-ContainerRegistryRestrictions {
    Write-Banner "Configuring Container Registry Restrictions"

    Invoke-ExternalBashScript `
        -ScriptName $Script:Config.BashScripts.ContainerRegistry `
        -WslDistro $Script:Config.WslDistro `
        -Description "Container Registry Restrictions Configuration" `
        -Variables @{
            INTERNAL_REGISTRY = $Script:Config.InternalRegistryUrl
        } `
        -ScriptRoot $Script:Config.ScriptRoot `
        -DryRun $Script:Config.DryRun `
        -LogFunction ${function:Write-Log}

    Write-Log "Container registry restrictions configuration complete" -Level SUCCESS
}

function Set-RootlessMode {
    Write-Banner "Configuring Rootless Mode"

    Invoke-ExternalBashScript `
        -ScriptName $Script:Config.BashScripts.RootlessMode `
        -WslDistro $Script:Config.WslDistro `
        -Description "Rootless Mode Configuration" `
        -ScriptRoot $Script:Config.ScriptRoot `
        -DryRun $Script:Config.DryRun `
        -LogFunction ${function:Write-Log}

    Write-Log "Rootless mode configuration complete" -Level SUCCESS
}

function Set-LinuxFirewall {
    Write-Banner "Configuring Linux Firewall"

    Invoke-ExternalBashScript `
        -ScriptName $Script:Config.BashScripts.LinuxFirewall `
        -WslDistro $Script:Config.WslDistro `
        -Description "Linux Firewall Configuration" `
        -Variables @{
            DNS_SERVER = $Script:Config.InternalDnsServer
        } `
        -ScriptRoot $Script:Config.ScriptRoot `
        -DryRun $Script:Config.DryRun `
        -LogFunction ${function:Write-Log}

    Write-Log "Linux firewall configuration complete" -Level SUCCESS
}

function Set-DnsConfiguration {
    Write-Banner "Configuring DNS"

    Invoke-ExternalBashScript `
        -ScriptName $Script:Config.BashScripts.DnsConfiguration `
        -WslDistro $Script:Config.WslDistro `
        -Description "DNS Configuration" `
        -Variables @{
            DNS_SERVER = $Script:Config.InternalDnsServer
        } `
        -ScriptRoot $Script:Config.ScriptRoot `
        -DryRun $Script:Config.DryRun `
        -LogFunction ${function:Write-Log}

    Write-Log "DNS configuration complete" -Level SUCCESS
}

function Set-ProxyConfiguration {
    Write-Banner "Configuring Proxy"

    Invoke-ExternalBashScript `
        -ScriptName $Script:Config.BashScripts.ProxyConfiguration `
        -WslDistro $Script:Config.WslDistro `
        -Description "Proxy Configuration" `
        -Variables @{
            PROXY_URL = $Script:Config.InternalProxyUrl
        } `
        -ScriptRoot $Script:Config.ScriptRoot `
        -DryRun $Script:Config.DryRun `
        -LogFunction ${function:Write-Log}

    Write-Log "Proxy configuration complete" -Level SUCCESS
}

# ============================================================================
# PATCHING SCRIPTS DEPLOYMENT
# ============================================================================

function Deploy-PatchingScripts {
    Write-Banner "Deploying Patching Scripts"

    Invoke-ExternalBashScript `
        -ScriptName $Script:Config.BashScripts.PatchingScripts `
        -WslDistro $Script:Config.WslDistro `
        -Description "Patching Scripts Deployment" `
        -ScriptRoot $Script:Config.ScriptRoot `
        -DryRun $Script:Config.DryRun `
        -LogFunction ${function:Write-Log}

    Write-Log "Patching scripts deployment complete" -Level SUCCESS
}

# ============================================================================
# VERIFICATION
# ============================================================================

function Invoke-Verification {
    Write-Banner "Verifying Configuration"
    
    if ($DryRun) {
        Write-Log "Skipping verification in dry run mode" -Level WARN
        return
    }
    
    # Check if standalone test script exists in same directory
    $testScriptPath = Join-Path $PSScriptRoot "Test-PodmanSecurity.ps1"
    
    if (Test-Path $testScriptPath) {
        Write-Log "Using standalone verification script: $testScriptPath"
        & $testScriptPath -WslDistro $WslDistro
    } else {
        # Fallback to inline verification if standalone script not found
        Write-Log "Standalone test script not found, using inline verification" -Level DEBUG
        Invoke-InlineVerification
    }
}

function Invoke-InlineVerification {
    Invoke-ExternalBashScript `
        -ScriptName $Script:Config.BashScripts.Verification `
        -WslDistro $Script:Config.WslDistro `
        -Description "Configuration Verification" `
        -ScriptRoot $Script:Config.ScriptRoot `
        -DryRun $Script:Config.DryRun `
        -LogFunction ${function:Write-Log}

    if ($LASTEXITCODE -eq 0) {
        Write-Log "All verification checks passed" -Level SUCCESS
    } else {
        Write-Log "Some verification checks failed" -Level WARN
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Main {
    try {
        Initialize-Environment
        
        if (-not $SkipPrerequisiteCheck) {
            Test-Prerequisites
        }
        
        # Backup existing configurations (uses external script if available)
        Invoke-Backup
        
        # Windows configurations
        Set-WslConfig
        Set-WindowsFirewall
        
        # WSL/Linux configurations
        Set-SshSecurity
        Set-RepositoryRestrictions
        Set-ContainerRegistryRestrictions
        Set-RootlessMode
        Set-LinuxFirewall
        Set-DnsConfiguration
        Set-ProxyConfiguration
        
        # Deploy patching infrastructure
        Deploy-PatchingScripts
        
        # Verify configuration (uses external script if available)
        Invoke-Verification
        
        # Restart WSL to apply changes
        if (-not $DryRun) {
            Write-Banner "Restarting WSL"
            wsl --shutdown
            Start-Sleep -Seconds 3
            Write-Log "WSL restarted. Starting distribution..."
            wsl -d $WslDistro -- echo "WSL started successfully"
        }
        
        Write-Banner "Setup Complete"
        Write-Log "Podman security configuration completed successfully!" -Level SUCCESS
        Write-Log ""
        Write-Log "Backup location: $($Script:Config.BackupDir)" -Level INFO
        Write-Log "To rollback, use: .\Rollback-PodmanSecurity.ps1 -BackupPath `"$($Script:Config.BackupDir)`"" -Level INFO
        Write-Log ""
        Write-Log "Next steps:" -Level INFO
        Write-Log "  1. Test Podman functionality: wsl -d $WslDistro -- podman info" -Level INFO
        Write-Log "  2. Run health check: wsl -d $WslDistro -- /opt/podman-security/scripts/health-check.sh" -Level INFO
        Write-Log "  3. Review logs in: $($Script:Config.BackupDir)" -Level INFO
        
    } catch {
        Write-Log "Setup failed: $_" -Level ERROR
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level DEBUG
        
        if ($Script:Config.BackupDir -and (Test-Path $Script:Config.BackupDir)) {
            Write-Log "Backups preserved at: $($Script:Config.BackupDir)" -Level WARN
            Write-Log "To rollback, use: .\Rollback-PodmanSecurity.ps1 -BackupPath `"$($Script:Config.BackupDir)`"" -Level WARN
        }
        
        throw
    }
}

# Run main function
Main
