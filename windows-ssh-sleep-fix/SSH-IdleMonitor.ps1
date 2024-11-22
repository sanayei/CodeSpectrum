# File: C:\Scripts\SSH-IdleMonitor.ps1

# Create logs directory and set up logging
$logPath = "C:\Scripts\ssh-monitor.log"
$logDir = Split-Path -Parent $logPath
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$timestamp] [$Type] $Message"
}

function Get-SSHConnections {
    [CmdletBinding()]
    param()
    
    try {
        $sshConnections = Get-NetTCPConnection -State Established | 
            Where-Object { $_.LocalPort -eq 22 -or $_.RemotePort -eq 22 } |
            ForEach-Object {
                $remotePort = if ($_.LocalPort -eq 22) { $_.RemotePort } else { $_.LocalPort }
                $process = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                
                [PSCustomObject]@{
                    LocalAddress  = $_.LocalAddress
                    LocalPort    = $_.LocalPort
                    RemoteAddress = $_.RemoteAddress
                    RemotePort   = $remotePort
                    State        = $_.State
                    ProcessId    = $_.OwningProcess
                    ProcessName  = $process.ProcessName
                    CreationTime = $process.StartTime
                }
            }

        if ($sshConnections) {
            return @{
                HasConnections = $true
                Connections   = @($sshConnections)
                Count        = @($sshConnections).Count
                Message      = "Active SSH connections found"
            }
        } else {
            return @{
                HasConnections = $false
                Connections   = @()
                Count        = 0
                Message      = "No active SSH connections"
            }
        }
    }
    catch {
        Write-Log "Error checking SSH connections: $_" "ERROR"
        return @{
            HasConnections = $false
            Connections   = @()
            Count        = 0
            Message      = "Error checking SSH connections: $_"
        }
    }
}

function Start-KeepAwake {
    try {
        # Load the required kernel32.dll method
        $signature = @'
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern uint SetThreadExecutionState(uint esFlags);
        
        public const uint ES_CONTINUOUS = 0x80000000;
        public const uint ES_SYSTEM_REQUIRED = 0x00000001;
        public const uint ES_DISPLAY_REQUIRED = 0x00000002;
        public const uint ES_AWAYMODE_REQUIRED = 0x00000040;
'@
        Add-Type -MemberDefinition $signature -Name PowerState -Namespace Win32

        # Create shell application object for mouse movement
        $shell = New-Object -ComObject "WScript.Shell"
        
        Write-Log "Starting keep-awake loop" "INFO"
        
        Do {
            # Prevent system sleep
            [Win32.PowerState]::SetThreadExecutionState(
                [Win32.PowerState]::ES_CONTINUOUS -bor
                [Win32.PowerState]::ES_SYSTEM_REQUIRED -bor
                [Win32.PowerState]::ES_DISPLAY_REQUIRED -bor
                [Win32.PowerState]::ES_AWAYMODE_REQUIRED
            )

            # Send a null keystroke to prevent screen saver
            $shell.SendKeys("")
            
            Write-Log "Keeping system awake..." "DEBUG"
            Start-Sleep -Seconds 180  # 3 minutes
            
            # Check if we still have SSH connections
            $sshStatus = Get-SSHConnections
            if (-not $sshStatus.HasConnections) {
                Write-Log "No more active SSH connections - stopping keep-awake" "INFO"
                break
            }
        } While ($true)
    }
    catch {
        Write-Log "Error in keep-awake loop: $_" "ERROR"
    }
    finally {
        # Reset power state to normal
        try {
            [Win32.PowerState]::SetThreadExecutionState([Win32.PowerState]::ES_CONTINUOUS)
            Write-Log "Reset power state to normal" "INFO"
        }
        catch {
            Write-Log "Error resetting power state: $_" "ERROR"
        }
        
        # Release COM object
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        
        Write-Log "Keep-awake loop terminated" "INFO"
    }
}

# Main execution block
try {
    Write-Log "Script started" "INFO"
    
    # Check for SSH connections
    $sshStatus = Get-SSHConnections
    
    if ($sshStatus.HasConnections) {
        Write-Log "Found $($sshStatus.Count) active SSH connection(s)" "INFO"
        
        foreach ($conn in $sshStatus.Connections) {
            Write-Log "Connection details: $($conn.RemoteAddress):$($conn.RemotePort) via $($conn.ProcessName) (PID: $($conn.ProcessId))" "INFO"
        }
        
        # Start keep-awake process
        Start-KeepAwake
    }
    else {
        Write-Log "No active SSH connections - Allowing normal sleep behavior" "INFO"
    }
}
catch {
    Write-Log "Critical error in main execution block: $_" "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
}
finally {
    Write-Log "Script execution completed" "INFO"
    Write-Log "----------------------------------------" "INFO"
}