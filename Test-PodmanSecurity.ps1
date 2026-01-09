<#
.SYNOPSIS
    Podman Security Configuration Verification Script
    
.DESCRIPTION
    Verifies that all Podman security configurations are correctly applied.
    Can be run independently to check the security posture at any time.
    
.PARAMETER WslDistro
    Name of the WSL distribution to verify (default: podman-machine-default)
    
.PARAMETER Detailed
    Show detailed output for each check
    
.EXAMPLE
    .\Test-PodmanSecurity.ps1
    
.EXAMPLE
    .\Test-PodmanSecurity.ps1 -WslDistro "my-podman" -Detailed
    
.NOTES
    Author: Infrastructure/Security Engineering
    Version: 1.0
#>

[CmdletBinding()]
param(
    [string]$WslDistro = "podman-machine-default",
    [switch]$Detailed
)

$ErrorActionPreference = "Stop"

# Import shared module
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
        "DEBUG"   { if ($Detailed) { Write-Host $logMessage -ForegroundColor Gray } }
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

function Test-WindowsConfiguration {
    Write-Log "Checking Windows configurations..." -Level INFO
    
    $results = @{
        Passed = 0
        Failed = 0
        Checks = @()
    }
    
    # Check .wslconfig exists
    $wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
    if (Test-Path $wslConfigPath) {
        $results.Passed++
        $results.Checks += @{ Name = ".wslconfig exists"; Status = "PASS" }
        Write-Log ".wslconfig exists: PASS" -Level SUCCESS
        
        # Check for mirrored networking
        $content = Get-Content $wslConfigPath -Raw
        if ($content -match "networkingMode\s*=\s*mirrored") {
            $results.Passed++
            $results.Checks += @{ Name = "Mirrored networking configured"; Status = "PASS" }
            Write-Log "Mirrored networking configured: PASS" -Level SUCCESS
        } else {
            $results.Failed++
            $results.Checks += @{ Name = "Mirrored networking configured"; Status = "FAIL" }
            Write-Log "Mirrored networking configured: FAIL" -Level ERROR
        }
    } else {
        $results.Failed++
        $results.Checks += @{ Name = ".wslconfig exists"; Status = "FAIL" }
        Write-Log ".wslconfig exists: FAIL" -Level ERROR
    }
    
    # Check firewall rules
    $podmanRules = Get-NetFirewallRule -DisplayName "Podman-*" -ErrorAction SilentlyContinue
    if ($podmanRules) {
        $blockRule = $podmanRules | Where-Object { $_.DisplayName -eq "Podman-Block-WSL-Outbound" }
        $allowRule = $podmanRules | Where-Object { $_.DisplayName -eq "Podman-Allow-WSL-Internal" }
        
        if ($blockRule -and $blockRule.Enabled -eq "True") {
            $results.Passed++
            $results.Checks += @{ Name = "Outbound block rule active"; Status = "PASS" }
            Write-Log "Outbound block rule active: PASS" -Level SUCCESS
        } else {
            $results.Failed++
            $results.Checks += @{ Name = "Outbound block rule active"; Status = "FAIL" }
            Write-Log "Outbound block rule active: FAIL" -Level ERROR
        }
        
        if ($allowRule -and $allowRule.Enabled -eq "True") {
            $results.Passed++
            $results.Checks += @{ Name = "Internal allow rule active"; Status = "PASS" }
            Write-Log "Internal allow rule active: PASS" -Level SUCCESS
        } else {
            $results.Failed++
            $results.Checks += @{ Name = "Internal allow rule active"; Status = "FAIL" }
            Write-Log "Internal allow rule active: FAIL" -Level ERROR
        }
    } else {
        $results.Failed += 2
        $results.Checks += @{ Name = "Firewall rules exist"; Status = "FAIL" }
        Write-Log "Podman firewall rules not found: FAIL" -Level ERROR
    }
    
    return $results
}

function Test-WslConfiguration {
    param([string]$Distro)

    Write-Log "Checking WSL configurations in '$Distro'..." -Level INFO

    try {
        # Use the shared module to execute the external bash script
        Invoke-ExternalBashScript `
            -ScriptName "test-wsl-configuration.sh" `
            -WslDistro $Distro `
            -Description "WSL Configuration Verification" `
            -ScriptRoot $PSScriptRoot `
            -UseSudo $false `
            -DryRun $false `
            -LogFunction ${function:Write-Log}

        $exitCode = $LASTEXITCODE
        return @{
            Passed = ($exitCode -eq 0)
            FailCount = $exitCode
        }
    } catch {
        Write-Log "WSL configuration test failed: $_" -Level ERROR
        return @{
            Passed = $false
            FailCount = 999
        }
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Banner "Podman Security Verification"

Write-Log "WSL Distribution: $WslDistro" -Level INFO
Write-Log ""

# Check if WSL distribution exists
$distros = wsl --list --quiet 2>&1
if ($distros -notcontains $WslDistro) {
    Write-Log "WSL distribution '$WslDistro' not found" -Level ERROR
    Write-Log "Available distributions:" -Level INFO
    wsl --list --verbose
    exit 1
}

# Run Windows checks
Write-Banner "Windows Configuration Checks"
$windowsResults = Test-WindowsConfiguration

# Run WSL checks
Write-Banner "WSL Configuration Checks"
$wslResults = Test-WslConfiguration -Distro $WslDistro

# Summary
Write-Banner "Verification Summary"

$totalPassed = $windowsResults.Passed
$totalFailed = $windowsResults.Failed + $wslResults.FailCount

if ($totalFailed -eq 0) {
    Write-Log "All security checks passed!" -Level SUCCESS
    exit 0
} else {
    Write-Log "Some checks failed. Review the output above." -Level WARN
    Write-Log "Windows: $($windowsResults.Passed) passed, $($windowsResults.Failed) failed" -Level INFO
    Write-Log "WSL: $($wslResults.FailCount) failed" -Level INFO
    exit 1
}
