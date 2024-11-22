# Preventing Windows 11 Sleep During Active SSH Sessions: A Reliable PowerShell Solution

## Understanding the Challenge

When working with Windows 11 through SSH, users often face an annoying issue: the system goes to sleep during active SSH sessions because Windows doesn't recognize these connections as active user interactions. This can be particularly frustrating when:
- You're in the middle of a remote operation
- Running long-term processes
- Managing servers remotely
- Performing system maintenance

The immediate solution might seem to be disabling sleep mode entirely, but this isn't ideal because:
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

## Implementation

Let's break down the solution into its core components.

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
        # Return structured information about connections
    }
}
```

This function:
- Identifies all established SSH connections
- Gathers detailed connection information
- Provides process details for each connection
- Returns a structured object for easy handling

### 2. Keep-Awake Mechanism

The heart of our solution uses Windows Forms to prevent sleep reliably:

```powershell
function Start-KeepAwake {
    param (
        [System.Windows.Forms.Form]$Form
    )
    try {
        Do {
            $Form.Activate()
            [System.Windows.Forms.SendKeys]::SendWait("{BS}")
            [System.Windows.Forms.SendKeys]::SendWait(".")
            Start-Sleep -Milliseconds 180000  # 3 minutes
            
            # Check for active connections
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
}
```

This approach:
- Creates a hidden form to capture input
- Simulates keyboard activity every 3 minutes
- Continuously monitors SSH connections
- Automatically stops when connections end

### 3. Main Execution Logic

The main script ties everything together:

```powershell
try {
    Write-Log "Script started" "INFO"
    
    $sshStatus = Get-SSHConnections
    
    if ($sshStatus.HasConnections) {
        Write-Log "Found $($sshStatus.Count) active SSH connection(s)" "INFO"
        
        # Create and configure the form
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'SSH Keep-Awake'
        $form.Size = New-Object System.Drawing.Size(200,100)
        $form.StartPosition = 'Manual'
        $form.Location = New-Object System.Drawing.Point(1500,670)
        
        # Add textbox for input simulation
        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.Size = New-Object System.Drawing.Size(200,100)
        $textBox.Multiline = $true
        $form.Controls.Add($textBox)
        $form.Topmost = $true
        
        # Initialize and start keep-awake
        $form.Add_Shown({$textBox.Select()})
        $form.Show()
        
        Start-Sleep -Milliseconds 1000
        Start-KeepAwake -Form $form
        
        $form.Close()
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

3. Create a scheduled task that:
- Triggers when the system becomes idle
- Runs with highest privileges
- Executes the PowerShell script

## How It Works

1. The system enters an idle state
2. Task Scheduler triggers our script
3. Script checks for SSH connections
4. If connections exist:
   - Creates a hidden Windows Form
   - Simulates periodic keyboard input
   - Monitors for active connections
   - Logs all activities
5. When connections end:
   - Closes the form
   - Allows normal sleep behavior
   - Logs completion

## Monitoring and Troubleshooting

The script maintains a detailed log at `C:\Scripts\ssh-monitor.log`:
```
[2024-11-21 21:21:11] [INFO] Script started
[2024-11-21 21:21:11] [INFO] Found 2 active SSH connection(s)
[2024-11-21 21:21:11] [INFO] Connection details: 192.168.1.100:54321 via sshd (PID: 1234)
[2024-11-21 21:21:11] [INFO] Keep-awake form initialized
```

## Benefits of This Approach

1. **Reliability**: Uses Windows Forms for guaranteed input simulation
2. **Efficiency**: Only activates when needed
3. **Automatic**: No manual intervention required
4. **Self-monitoring**: Continuously checks connection status
5. **Clean**: Proper cleanup when connections end
6. **Traceable**: Detailed logging for troubleshooting

## Conclusion

This solution provides a reliable way to prevent Windows 11 from sleeping during SSH sessions while maintaining power efficiency. The Windows Forms approach ensures consistent behavior, while the monitoring system prevents unnecessary power consumption when connections end.

By simulating actual user input rather than relying on API calls, this solution works more reliably than traditional approaches. It's a practical balance between maintaining remote accessibility and efficient power management.

---

*Have questions or suggestions? Feel free to comment below or contribute to the project!*

## References

1. Krishnamoorthy, R. (2023). "How to prevent computer from sleep and stay awake always script". DevGenius. https://blog.devgenius.io/how-to-prevent-computer-from-sleep-and-stay-awake-always-script-74a8906a7629

---

*Have questions or suggestions? Feel free to comment below or contribute to the project!*