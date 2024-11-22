# First, create the main script that will be triggered
$monitorScriptContent = @'
# Create logs directory if it doesn't exist
$logPath = "C:\Scripts\ssh-monitor.log"
$logDir = Split-Path -Parent $logPath
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force
}

# Function to check if there are active SSH connections
function Get-ActiveSSHConnections {
    $sshConnections = Get-NetTCPConnection -State Established | 
        Where-Object { $_.LocalPort -eq 22 -or $_.RemotePort -eq 22 }
    return $sshConnections.Count -gt 0
}

# Function to simulate user activity
function Reset-IdleTimer {
    Add-Type -AssemblyName System.Windows.Forms
    $currentPosition = [System.Windows.Forms.Cursor]::Position
    
    # Move cursor 1 pixel right and back
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($currentPosition.X + 1, $currentPosition.Y)
    Start-Sleep -Milliseconds 100
    [System.Windows.Forms.Cursor]::Position = $currentPosition
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$timestamp] Idle timer reset due to active SSH connection"
}

# Check for SSH connections and reset if needed
if (Get-ActiveSSHConnections) {
    Reset-IdleTimer
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$timestamp] Active SSH connection found - Reset idle timer"
} else {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$timestamp] No active SSH connections found - Allowing system to idle"
}
'@

# Create script directory and save the monitor script
$scriptPath = "C:\Scripts\SSH-IdleMonitor.ps1"
$scriptDir = Split-Path -Parent $scriptPath
if (!(Test-Path $scriptDir)) {
    New-Item -ItemType Directory -Path $scriptDir -Force
}
Set-Content -Path $scriptPath -Value $monitorScriptContent

# Create the scheduled task
$taskName = "SSHIdleMonitor"
$taskDescription = "Checks for SSH connections when system becomes idle"

# Create XML for the task with idle trigger
$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <IdleTrigger>
      <Enabled>true</Enabled>
    </IdleTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfIdle>true</RunOnlyIfIdle>
    <IdleSettings>
      <Duration>PT3M</Duration>
      <WaitTimeout>PT3M</WaitTimeout>
      <StopOnIdleEnd>true</StopOnIdleEnd>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT1M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -WindowStyle Hidden -File "$scriptPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

# Remove existing task if it exists
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Register the new task using XML
Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force

Write-Host @"
Task created successfully. Setup details:

1. Monitor script location: $scriptPath
2. Task Name: $taskName
3. Log file location: C:\Scripts\ssh-monitor.log
4. Trigger: When system is idle for 3 minutes
5. Behavior: Runs once per idle event to check for SSH connections

The task will:
- Trigger when the system has been idle for 3 minutes
- Check for active SSH connections
- If found, reset the idle timer
- If not found, allow system to enter sleep mode
- Wait for next idle trigger to check again

Monitor the log file to see when the task runs:
notepad C:\Scripts\ssh-monitor.log

"@
