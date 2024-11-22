# Preventing Windows 11 Sleep During Active SSH Sessions: A Robust PowerShell Solution

## Understanding the Challenge

When working with Windows 11 through SSH, users often encounter a significant issue: the system goes to sleep during active SSH sessions because Windows doesn't recognize these connections as active user interactions. This can be particularly frustrating when:
- You're in the middle of a remote operation
- Running long-term processes
- Managing servers remotely
- Performing system maintenance

While completely disabling sleep mode might seem like an easy solution, it's not ideal because:
- It wastes energy when the system isn't in use
- Increases power consumption unnecessarily
- Can lead to higher electricity costs
- Places unnecessary wear on hardware
- Isn't environmentally friendly

## A Smart Solution

Instead of completely disabling sleep, we can create an intelligent PowerShell solution that:
1. Detects when the system becomes idle
2. Checks for active SSH connections
3. Keeps the system awake only when needed
4. Returns to normal power management when SSH sessions end

## The Implementation

Let's break down our solution into its core components.

### 1. SSH Connection Detection

First, we need reliable SSH connection detection:

```powershell
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
        # Return connection information...
    }
}
```

This function:
- Identifies all established SSH connections
- Gathers detailed connection information
- Provides process details for each connection
- Returns a structured object for easy handling

### 2. Keep-Awake Mechanism

The heart of our solution uses a combination of Windows APIs and shell automation:

```powershell
function Start-KeepAwake {
    try {
        # Load the kernel32.dll method
        $signature = @'
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern uint SetThreadExecutionState(uint esFlags);
        
        public const uint ES_CONTINUOUS = 0x80000000;
        public const uint ES_SYSTEM_REQUIRED = 0x00000001;
        public const uint ES_DISPLAY_REQUIRED = 0x00000002;
        public const uint ES_AWAYMODE_REQUIRED = 0x00000040;
'@
        Add-Type -MemberDefinition $signature -Name PowerState -Namespace Win32

        # Create shell automation object
        $shell = New-Object -ComObject "WScript.Shell"
        
        Do {
            # Prevent system sleep using multiple methods
            [Win32.PowerState]::SetThreadExecutionState(
                [Win32.PowerState]::ES_CONTINUOUS -bor
                [Win32.PowerState]::ES_SYSTEM_REQUIRED -bor
                [Win32.PowerState]::ES_DISPLAY_REQUIRED -bor
                [Win32.PowerState]::ES_AWAYMODE_REQUIRED
            )

            $shell.SendKeys("")
            Start-Sleep -Seconds 180  # Check every 3 minutes
            
            # Continue only if SSH connections exist
            $sshStatus = Get-SSHConnections
            if (-not $sshStatus.HasConnections) {
                break
            }
        } While ($true)
    }
    finally {
        # Cleanup and restore normal power state
        [Win32.PowerState]::SetThreadExecutionState([Win32.PowerState]::ES_CONTINUOUS)
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell)
    }
}
```

This approach:
- Uses Windows kernel API for system-level power management
- Implements shell automation for activity simulation
- Includes proper resource cleanup
- Continuously monitors connection status

### 3. Logging System

Robust logging helps track system behavior:

```powershell
function Write-Log {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$timestamp] [$Type] $Message"
}
```

### 4. Main Execution Logic

The script ties everything together:

```powershell
try {
    Write-Log "Script started" "INFO"
    
    $sshStatus = Get-SSHConnections
    
    if ($sshStatus.HasConnections) {
        Write-Log "Found $($sshStatus.Count) active SSH connection(s)" "INFO"
        
        foreach ($conn in $sshStatus.Connections) {
            Write-Log "Connection details: $($conn.RemoteAddress):$($conn.RemotePort)" "INFO"
        }
        
        Start-KeepAwake
    }
    else {
        Write-Log "No active SSH connections - Allowing normal sleep behavior" "INFO"
    }
}
finally {
    Write-Log "Script execution completed" "INFO"
}
```

## Setting Up the Solution

1. Create the scripts directory:
```powershell
mkdir C:\Scripts
```

2. Save the complete script as `C:\Scripts\SSH-IdleMonitor.ps1`

3. Create a scheduled task:
```powershell
# Task configuration details in XML format...
```

## How It Works

1. System enters idle state
2. Task Scheduler triggers our script
3. Script checks for SSH connections
4. If connections exist:
   - Activates multiple sleep prevention methods
   - Monitors connection status
   - Maintains system activity
   - Logs all actions
5. When connections end:
   - Cleans up resources
   - Restores normal power management
   - Logs completion

## Monitoring

Monitor the solution through `C:\Scripts\ssh-monitor.log`:
```
[2024-11-22 04:52:23] [INFO] Script started
[2024-11-22 04:52:23] [INFO] Found 2 active SSH connections
[2024-11-22 04:52:23] [INFO] Keeping system awake...
```

## Benefits of This Approach

1. **Reliability**: Uses multiple system-level methods
2. **Efficiency**: Only activates when needed
3. **Clean**: Proper resource management
4. **Traceable**: Detailed logging
5. **Robust**: Multiple fallback mechanisms

## Technical Details

This solution combines several approaches:
1. `SetThreadExecutionState` for system-level power management
2. Shell automation for activity simulation
3. Connection monitoring for automatic management
4. Resource cleanup for system stability

## Conclusion

This enhanced solution provides a robust and reliable way to prevent Windows 11 from sleeping during SSH sessions while maintaining power efficiency. By using system-level APIs and proper resource management, it ensures consistent behavior without requiring elevated UI privileges.

## Credits

Credit for the original Windows sleep prevention concepts:
- Ranjith Krishnamoorthy's article on [DevGenius](https://blog.devgenius.io/how-to-prevent-computer-from-sleep-and-stay-awake-always-script-74a8906a7629)
- Windows API documentation and community contributions

---

*Have questions or suggestions? Feel free to comment below or contribute to the project!*