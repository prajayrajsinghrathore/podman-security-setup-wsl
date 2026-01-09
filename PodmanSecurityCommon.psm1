# PodmanSecurityCommon.psm1
# Shared module for Podman Security Setup scripts
# Contains common functions for executing bash scripts in WSL

# Default subdirectory for WSL bash scripts
$Script:WslScriptsFolder = "wsl-scripts"

function Invoke-ExternalBashScript {
    <#
    .SYNOPSIS
        Executes an external bash script file in WSL with variable substitution

    .PARAMETER ScriptName
        The name of the bash script file to execute

    .PARAMETER WslDistro
        Name of the WSL distribution to execute the script in

    .PARAMETER Description
        Description of what the script does (for logging)

    .PARAMETER Variables
        Hashtable of variables to pass to the bash script (uses {{KEY}} placeholder substitution)

    .PARAMETER ScriptRoot
        Root directory where the bash script is located (defaults to calling script's directory)

    .PARAMETER UseSudo
        Whether to run the script with sudo (default: $true)

    .PARAMETER DryRun
        If true, only shows what would be executed without running it

    .PARAMETER LogFunction
        Optional scriptblock for logging (receives Message and Level parameters)

    .EXAMPLE
        Invoke-ExternalBashScript -ScriptName "configure-ssh.sh" -WslDistro "podman-machine-default" -Description "SSH Configuration"

    .EXAMPLE
        Invoke-ExternalBashScript -ScriptName "configure-dns.sh" -WslDistro "ubuntu" -Variables @{DNS_SERVER="10.0.0.1"} -Description "DNS Setup"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName,

        [Parameter(Mandatory)]
        [string]$WslDistro,

        [Parameter(Mandatory)]
        [string]$Description,

        [hashtable]$Variables = @{},

        [string]$ScriptRoot = $PSScriptRoot,

        [bool]$UseSudo = $true,

        [bool]$DryRun = $false,

        [scriptblock]$LogFunction = $null
    )

    # Helper function for logging
    function Write-LogMessage {
        param($Message, $Level = "INFO")
        if ($LogFunction) {
            & $LogFunction -Message $Message -Level $Level
        } else {
            $color = switch ($Level) {
                "DEBUG" { "Gray" }
                "INFO" { "Cyan" }
                "WARN" { "Yellow" }
                "ERROR" { "Red" }
                "SUCCESS" { "Green" }
                default { "White" }
            }
            Write-Host "[$Level] $Message" -ForegroundColor $color
        }
    }

    Write-LogMessage "Executing: $Description" "INFO"

    if ($DryRun) {
        Write-LogMessage "DRY RUN: Would execute external bash script: $ScriptName" "DEBUG"
        if ($Variables.Count -gt 0) {
            Write-LogMessage "DRY RUN: With variables: $($Variables.Keys -join ', ')" "DEBUG"
        }
        return
    }

    # Check if script exists - first try in wsl-scripts subfolder, then in ScriptRoot directly
    $scriptPath = Join-Path $ScriptRoot (Join-Path $Script:WslScriptsFolder $ScriptName)
    if (-not (Test-Path $scriptPath)) {
        # Fallback to ScriptRoot directly for backwards compatibility
        $scriptPath = Join-Path $ScriptRoot $ScriptName
        if (-not (Test-Path $scriptPath)) {
            throw "Required bash script not found: $ScriptName (searched in $Script:WslScriptsFolder and root)"
        }
    }

    Write-LogMessage "Using external bash script: $scriptPath" "DEBUG"

    # Create temp copy for WSL execution
    $tempScript = [System.IO.Path]::GetTempFileName()

    try {
        # Read script content and perform variable substitution
        $scriptContent = Get-Content $scriptPath -Raw

        # Replace PowerShell variables with actual values
        foreach ($key in $Variables.Keys) {
            $scriptContent = $scriptContent -replace "\{\{$key\}\}", $Variables[$key]
        }

        # Write substituted content to temp file
        $scriptContent | Out-File -FilePath $tempScript -Encoding utf8 -NoNewline

        # Convert path and execute
        $wslPath = wsl -d $WslDistro -- wslpath -u ($tempScript -replace '\\', '/')

        # Build execution command
        $sudoPrefix = if ($UseSudo) { "sudo " } else { "" }
        $execCommand = "sed -i 's/\r$//' '$wslPath' && chmod +x '$wslPath' && ${sudoPrefix}bash '$wslPath'"

        wsl -d $WslDistro -- bash -c $execCommand

        if ($LASTEXITCODE -ne 0) {
            throw "External bash script execution failed with exit code $LASTEXITCODE"
        }

        Write-LogMessage "$Description completed successfully" "SUCCESS"
    } finally {
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WslScript {
    <#
    .SYNOPSIS
        Executes an inline bash script content in WSL

    .PARAMETER ScriptContent
        The bash script content to execute

    .PARAMETER WslDistro
        Name of the WSL distribution to execute the script in

    .PARAMETER Description
        Description of what the script does (for logging)

    .PARAMETER UseSudo
        Whether to run the script with sudo (default: $true)

    .PARAMETER DryRun
        If true, only shows the script content without executing it

    .PARAMETER LogFunction
        Optional scriptblock for logging (receives Message and Level parameters)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptContent,

        [Parameter(Mandatory)]
        [string]$WslDistro,

        [string]$Description = "WSL Script",

        [bool]$UseSudo = $true,

        [bool]$DryRun = $false,

        [scriptblock]$LogFunction = $null
    )

    # Helper function for logging
    function Write-LogMessage {
        param($Message, $Level = "INFO")
        if ($LogFunction) {
            & $LogFunction -Message $Message -Level $Level
        } else {
            $color = switch ($Level) {
                "DEBUG" { "Gray" }
                "INFO" { "Cyan" }
                "WARN" { "Yellow" }
                "ERROR" { "Red" }
                "SUCCESS" { "Green" }
                default { "White" }
            }
            Write-Host "[$Level] $Message" -ForegroundColor $color
        }
    }

    Write-LogMessage "Executing: $Description" "INFO"

    if ($DryRun) {
        Write-Host "--- Script Content ---" -ForegroundColor Gray
        Write-Host $ScriptContent -ForegroundColor Gray
        Write-Host "--- End Script ---" -ForegroundColor Gray
        return
    }

    # Create temp script file
    $tempScript = [System.IO.Path]::GetTempFileName()
    $ScriptContent | Out-File -FilePath $tempScript -Encoding utf8 -NoNewline

    try {
        # Convert path and execute
        $wslPath = wsl -d $WslDistro -- wslpath -u ($tempScript -replace '\\', '/')

        # Build execution command
        $sudoPrefix = if ($UseSudo) { "sudo " } else { "" }
        $execCommand = "sed -i 's/\r$//' '$wslPath' && chmod +x '$wslPath' && ${sudoPrefix}bash '$wslPath'"

        wsl -d $WslDistro -- bash -c $execCommand

        if ($LASTEXITCODE -ne 0) {
            throw "WSL script execution failed with exit code $LASTEXITCODE"
        }
    } finally {
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
    }
}

# Export functions
Export-ModuleMember -Function Invoke-ExternalBashScript, Invoke-WslScript
