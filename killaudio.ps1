# Script: Monitor and Control NVIDIA Audio Devices
# Purpose: Automatically disable NVIDIA HD Audio devices and prevent them from becoming active
# Usage: Can be run directly or via IRM from GitHub

#Region Configuration
$script:Config = @{
    TaskName = "NvidiaAudioAutoDisable"
    ScriptDir = "C:\DeviceAudioAutoDisable"
    LogFile = "C:\DeviceAudioAutoDisable\AudioControl.log"
    DevicePattern = "*NVIDIA High Definition Audio*"
    RetryIntervalSeconds = 300  # 5 minutes
    MaxRetries = 3
    LongRetryIntervalMinutes = 30  # Time to wait before retrying after max retries exhausted
}
#EndRegion

#Region Logging
function Write-Log {
    [CmdletBinding()]
    param(
        [string]$Message,
        [ValidateSet('Info','Warning','Error','Debug')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    $logDir = Split-Path $script:Config.LogFile -Parent
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $script:Config.LogFile -Value $logMessage
    switch ($Level) {
        'Error' { Write-Error $Message }
        'Warning' { Write-Warning $Message }
        'Debug' { Write-Verbose $Message }
        default { Write-Host $logMessage }
    }
}
#EndRegion

#Region Validation
function Test-AdminAccess {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal $identity
        $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
        return $principal.IsInRole($adminRole)
    }
    catch {
        Write-Log "Error checking admin access: $_" -Level Error
        return $false
    }
}

function Test-SystemPermissions {
    try {
        # Test PnP cmdlet access
        $null = Get-PnpDevice -Class AudioEndpoint -ErrorAction Stop
        return $true
    }
    catch {
        Write-Log "Error testing PnP device access: $_" -Level Error
        return $false
    }
}

function Test-MonitorScript {
    param([string]$ScriptPath)
    
    if (!(Test-Path $ScriptPath)) {
        Write-Log "Monitor script not found at: $ScriptPath" -Level Error
        return $false
    }
    
    try {
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $ScriptPath), [ref]$null)
        return $true
    }
    catch {
        Write-Log "Syntax error in monitor script: $_" -Level Error
        return $false
    }
}
#EndRegion

#Region Device Management
function Disable-NvidiaAudioDevices {
    [CmdletBinding()]
    param(
        [switch]$Force
    )
    
    try {
        Write-Log "Scanning for NVIDIA audio devices..."
        
        $devices = Get-PnpDevice | Where-Object { 
            $_.FriendlyName -like $script:Config.DevicePattern -and 
            ($Force -or $_.Status -eq "OK")
        }
        
        $disabledCount = 0
        foreach ($dev in $devices) {
            Write-Log "Found device: $($dev.FriendlyName) (Status: $($dev.Status))"
            if ($Force -or $dev.Status -eq "OK") {
                Write-Log "Attempting to disable device: $($dev.FriendlyName)"
                Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false
                $disabledCount++
                Write-Log "Successfully disabled device: $($dev.FriendlyName)"
            }
        }
        
        if ($disabledCount -eq 0) {
            Write-Log "No active NVIDIA audio devices found that require disabling" -Level Info
        }
        else {
            Write-Log "Disabled $disabledCount device(s)" -Level Info
        }
        return $true
    }
    catch {
        Write-Log "Error disabling devices: $_" -Level Error
        return $false
    }
}
#EndRegion

#Region Monitor Script Generation
function New-MonitorScript {
    $monitorScriptPath = Join-Path $script:Config.ScriptDir "DeviceMonitor.ps1"
    $monitorContent = @'
param(
    [Parameter(Mandatory)]
    [string]$LogFile,
    [Parameter(Mandatory)]
    [string]$DevicePattern,
    [int]$RetryIntervalSeconds = 300,
    [int]$MaxRetries = 3,
    [int]$LongRetryIntervalMinutes = 30
)

# Import required functions
$script:LogFile = $LogFile
$script:EventRegistered = $false

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:LogFile -Value $logMessage
}

function Register-DeviceMonitor {
    param(
        [int]$RetryCount = 0
    )
    
    try {
        # Define device management action
        $action = {
            $devices = Get-PnpDevice -Class AudioEndpoint | Where-Object { 
                $_.FriendlyName -like $DevicePattern -and 
                $_.Status -eq "OK" 
            }
            
            foreach ($dev in $devices) {
                Write-Log "Monitor script: Disabling device $($dev.FriendlyName)"
                Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false
            }
        }

        # Register for specific device change events
        $query = @"
            SELECT * FROM Win32_DeviceChangeEvent 
            WHERE EventType = 2 
            AND TargetInstance ISA 'Win32_PnPEntity'
"@
        $null = Register-WmiEvent -Query $query -Action $action -ErrorAction Stop
        $script:EventRegistered = $true
        Write-Log "WMI Event subscription registered successfully"
        return $true
    }
    catch {
        Write-Log "Error registering WMI event (Attempt $($RetryCount + 1)): $_" -Level Error
        
        if ($RetryCount -lt $MaxRetries) {
            Write-Log "Retrying in $RetryIntervalSeconds seconds..."
            Start-Sleep -Seconds $RetryIntervalSeconds
            return Register-DeviceMonitor -RetryCount ($RetryCount + 1)
        }
        return $false
    }
}

# Initial device check and monitor registration
& $action.GetNewClosure()

while ($true) {
    if (-not $script:EventRegistered) {
        if (Register-DeviceMonitor) {
            Write-Log "Event monitoring initialized successfully"
        }
        else {
            Write-Log "Failed to initialize event monitor. Will retry in $LongRetryIntervalMinutes minutes" -Level Warning
            Start-Sleep -Seconds ($LongRetryIntervalMinutes * 60)
            continue
        }
    }
    
    # Periodic check as backup
    Start-Sleep -Seconds $RetryIntervalSeconds
    & $action.GetNewClosure()
}
'@

    if (!(Test-Path $script:Config.ScriptDir)) {
        New-Item -ItemType Directory -Path $script:Config.ScriptDir -Force | Out-Null
    }
    
    Set-Content -Path $monitorScriptPath -Value $monitorContent -Encoding UTF8
    
    if (-not (Test-MonitorScript -ScriptPath $monitorScriptPath)) {
        throw "Failed to validate monitor script"
    }
    
    return $monitorScriptPath
}
#EndRegion

#Region Service Management
function Install-AudioControl {
    try {
        Write-Log "Starting installation..."
        
        # Verify permissions
        if (-not (Test-AdminAccess)) {
            throw "Administrator privileges required"
        }
        
        if (-not (Test-SystemPermissions)) {
            throw "Insufficient system permissions to manage devices"
        }
        
        # Create monitor script
        $monitorScript = New-MonitorScript
        Write-Log "Monitor script created at: $monitorScript"
        
        # Build argument list carefully
        $scriptArguments = @(
            "-WindowStyle Hidden"
            "-ExecutionPolicy Bypass"
            "-File `"$monitorScript`""
            "-LogFile `"$($script:Config.LogFile)`""
            "-DevicePattern `"$($script:Config.DevicePattern)`""
            "-RetryIntervalSeconds $($script:Config.RetryIntervalSeconds)"
            "-MaxRetries $($script:Config.MaxRetries)"
            "-LongRetryIntervalMinutes $($script:Config.LongRetryIntervalMinutes)"
        ) -join ' '
        
        # Create scheduled task
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $scriptArguments
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -RunLevel Highest -LogonType ServiceAccount
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        
        Register-ScheduledTask -TaskName $script:Config.TaskName `
                             -Action $action `
                             -Trigger $trigger `
                             -Principal $principal `
                             -Settings $settings `
                             -Description "Automatically disable NVIDIA HD Audio devices" `
                             -Force
        
        Write-Log "Installation completed successfully"
        
        # Immediate first run
        Disable-NvidiaAudioDevices -Force
    }
    catch {
        Write-Log "Installation failed: $_" -Level Error
        throw
    }
}

function Uninstall-AudioControl {
    try {
        Write-Log "Starting uninstallation..."
        
        # Remove scheduled task
        if (Get-ScheduledTask -TaskName $script:Config.TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $script:Config.TaskName -Confirm:$false
            Write-Log "Scheduled task removed"
        }
        
        # Clean up script directory
        if (Test-Path $script:Config.ScriptDir) {
            Remove-Item $script:Config.ScriptDir -Recurse -Force
            Write-Log "Script directory removed"
        }
        
        Write-Log "Uninstallation completed successfully"
    }
    catch {
        Write-Log "Uninstallation failed: $_" -Level Error
        throw
    }
}
#EndRegion

#Region Main Menu
function Show-Menu {
    Write-Host "`nNVIDIA Audio Control Menu" -ForegroundColor Cyan
    Write-Host "1) Install and enable audio control"
    Write-Host "2) Uninstall and disable audio control"
    Write-Host "3) Check current status"
    Write-Host "4) View logs"
    Write-Host "5) Force immediate device check"
    Write-Host "Q) Quit"
    
    $choice = Read-Host "`nEnter your choice"
    
    switch ($choice) {
        '1' {
            Install-AudioControl
        }
        '2' {
            Uninstall-AudioControl
        }
        '3' {
            $task = Get-ScheduledTask -TaskName $script:Config.TaskName -ErrorAction SilentlyContinue
            if ($task) {
                Write-Host "`nStatus: Installed and $($task.State)"
                Write-Host "Last Run Time: $($task.LastRunTime)"
                Write-Host "Next Run Time: $($task.NextRunTime)"
                
                # Check current devices
                $devices = Get-PnpDevice | Where-Object { 
                    $_.FriendlyName -like $script:Config.DevicePattern
                }
                if ($devices) {
                    Write-Host "`nCurrent NVIDIA audio devices:"
                    $devices | Format-Table FriendlyName, Status -AutoSize
                }
            } else {
                Write-Host "`nStatus: Not installed"
            }
        }
        '4' {
            if (Test-Path $script:Config.LogFile) {
                Get-Content $script:Config.LogFile | Select-Object -Last 20
            } else {
                Write-Host "No logs found"
            }
        }
        '5' {
            Write-Host "Performing immediate device check..."
            Disable-NvidiaAudioDevices -Force
        }
        'Q' {
            return $false
        }
        default {
            Write-Host "Invalid choice" -ForegroundColor Red
        }
    }
    return $true
}

# Main execution
if ($MyInvocation.InvocationName -eq "&") {
    # Script is being run via IRM
    Install-AudioControl
} else {
    # Interactive mode
    do {
        $continue = Show-Menu
    } while ($continue)
}
