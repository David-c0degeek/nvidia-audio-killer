# Script: Monitor and Control NVIDIA Audio Devices
# Purpose: Automatically disable NVIDIA HD Audio devices in multi-monitor setups
# Usage: Can be run directly or via IRM from GitHub

#Region Configuration
$script:Config = @{
    TaskName = "NvidiaAudioAutoDisable"
    ScriptDir = "C:\DeviceAudioAutoDisable"
    LogFile = "C:\DeviceAudioAutoDisable\AudioControl.log"
    DevicePattern = "*NVIDIA High Definition Audio*"
    RetryIntervalSeconds = 300  # 5 minutes
    MaxRetries = 3
    LongRetryIntervalMinutes = 30
    LogCleanupDays = 7  # Cleanup logs older than 7 days
}
#EndRegion

#Region Logging
function Write-Log {
    [CmdletBinding()]
    param(
        [string]$Message,
        [ValidateSet('Info','Warning','Error','Success','Debug')]
        [string]$Level = 'Info',
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    # Add emoji/symbol based on level
    $symbol = switch ($Level) {
        'Success' { '✓' }
        'Warning' { '!' }
        'Error'   { '✕' }
        'Debug'   { '•' }
        default   { '•' }
    }
    
    $logMessage = "[$timestamp] [$Level] $symbol $Message"
    
    # Ensure log directory exists
    $logDir = Split-Path $script:Config.LogFile -Parent
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    # Clean up old logs
    Get-ChildItem -Path $logDir -Filter "*.log" | 
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$script:Config.LogCleanupDays) } | 
        Remove-Item -Force
    
    Add-Content -Path $script:Config.LogFile -Value $logMessage
    
    if (-not $NoConsole) {
        $color = switch ($Level) {
            'Success' { 'Green' }
            'Warning' { 'Yellow' }
            'Error'   { 'Red' }
            'Debug'   { 'Gray' }
            default   { 'White' }
        }
        Write-Host $logMessage -ForegroundColor $color
    }
}
#EndRegion

#Region Device Management
function Get-MonitorDetails {
    param(
        [Parameter(Mandatory)]
        [string]$DeviceName
    )
    
    # Extract monitor model and any additional info
    if ($DeviceName -match '(?<model>(LG ULTRAGEAR|27GL850)).*?(?<info>\(.*\))?') {
        return @{
            Model = $matches['model']
            Info = if ($matches['info']) { $matches['info'] } else { '' }
        }
    }
    return @{
        Model = $DeviceName
        Info = ''
    }
}

function Disable-NvidiaAudioDevices {
    [CmdletBinding()]
    param(
        [switch]$Force,
        [switch]$Quiet
    )
    
    try {
        if (-not $Quiet) {
            Write-Log "Starting NVIDIA audio device scan..." -Level Info
        }
        
        # Get all matching devices
        $devices = Get-PnpDevice | Where-Object { 
            $_.FriendlyName -like $script:Config.DevicePattern
        }
        
        $processedCount = 0
        $monitorCount = @{}
        
        foreach ($dev in $devices) {
            $monitorInfo = Get-MonitorDetails -DeviceName $dev.FriendlyName
            if (-not $monitorCount.ContainsKey($monitorInfo.Model)) {
                $monitorCount[$monitorInfo.Model] = 0
            }
            $monitorCount[$monitorInfo.Model]++
            
            $deviceDesc = "$($monitorInfo.Model) #$($monitorCount[$monitorInfo.Model])"
            
            if (-not $Quiet) {
                Write-Log "Processing: $deviceDesc $($monitorInfo.Info)" -Level Info
            }
            
            try {
                # Attempt to disable the device
                $null = Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction Stop
                if (-not $Quiet) {
                    Write-Log "Device disabled: $deviceDesc" -Level Success
                }
                $processedCount++
            }
            catch {
                $errorMsg = $_.Exception.Message
                
                # Handle common cases
                switch -Wildcard ($errorMsg) {
                    "*Generic failure*" {
                        if (-not $Quiet) {
                            Write-Log "Device processed: $deviceDesc (transition state)" -Level Success
                        }
                        $processedCount++
                    }
                    "*disabled*" {
                        if (-not $Quiet) {
                            Write-Log "Device verified: $deviceDesc (already disabled)" -Level Success
                        }
                        $processedCount++
                    }
                    default {
                        Write-Log "Error processing $deviceDesc: $errorMsg" -Level Warning
                    }
                }
            }
        }
        
        # Summary (only if not quiet)
        if (-not $Quiet) {
            if ($processedCount -eq 0) {
                Write-Log "No NVIDIA audio devices found requiring attention" -Level Info
            }
            else {
                Write-Log "Successfully processed $processedCount NVIDIA audio device(s)" -Level Success
                foreach ($monitor in $monitorCount.GetEnumerator()) {
                    Write-Log "- $($monitor.Key): $($monitor.Value) audio device(s)" -Level Debug
                }
            }
        }
        
        return $true
    }
    catch {
        Write-Log "Critical error in device management: $_" -Level Error
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

$script:Config = @{
    LogFile = $LogFile
    DevicePattern = $DevicePattern
}

# Import required functions (copied from main script)
${function:Write-Log} = ${function:Write-Log}
${function:Get-MonitorDetails} = ${function:Get-MonitorDetails}
${function:Disable-NvidiaAudioDevices} = ${function:Disable-NvidiaAudioDevices}

function Register-DeviceMonitor {
    param([int]$RetryCount = 0)
    
    try {
        # Define device management action
        $action = {
            Write-Log "Device change detected, running check..." -Level Debug -NoConsole
            Disable-NvidiaAudioDevices -Quiet
        }

        # Register for specific device change events with detailed query
        $query = @"
            SELECT * FROM Win32_DeviceChangeEvent 
            WHERE EventType = 2 
            AND TargetInstance ISA 'Win32_PnPEntity'
"@
        $null = Register-WmiEvent -Query $query -Action $action -ErrorAction Stop
        Write-Log "Device monitoring initialized successfully" -Level Success
        return $true
    }
    catch {
        Write-Log "Error registering device monitor (Attempt $($RetryCount + 1)): $_" -Level Error
        
        if ($RetryCount -lt $MaxRetries) {
            Write-Log "Retrying in $RetryIntervalSeconds seconds..." -Level Info
            Start-Sleep -Seconds $RetryIntervalSeconds
            return Register-DeviceMonitor -RetryCount ($RetryCount + 1)
        }
        return $false
    }
}

# Initial device check
Write-Log "Performing initial device check..." -Level Info
Disable-NvidiaAudioDevices

# Main monitoring loop
while ($true) {
    if (-not (Get-Variable -Name EventSubscriber -ErrorAction SilentlyContinue)) {
        Write-Log "Starting device monitor..." -Level Info
        if (Register-DeviceMonitor) {
            Write-Log "Monitor active and watching for device changes" -Level Success
        }
        else {
            Write-Log "Failed to initialize monitor, will retry in $LongRetryIntervalMinutes minutes" -Level Warning
            Start-Sleep -Seconds ($LongRetryIntervalMinutes * 60)
            continue
        }
    }
    
    # Periodic check
    Start-Sleep -Seconds $RetryIntervalSeconds
    Disable-NvidiaAudioDevices -Quiet
}
'@

    if (!(Test-Path $script:Config.ScriptDir)) {
        New-Item -ItemType Directory -Path $script:Config.ScriptDir -Force | Out-Null
    }
    
    Set-Content -Path $monitorScriptPath -Value $monitorContent -Encoding UTF8
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
