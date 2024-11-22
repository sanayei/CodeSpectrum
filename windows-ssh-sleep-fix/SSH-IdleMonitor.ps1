# File: C:\Scripts\SSH-IdleMonitor.ps1

# Create logs directory and set up logging
$logPath = "C:\scripts\ssh-monitor.log"
$logDir = Split-Path -Parent $logPath
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force
}

# Load required assemblies
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
    param (
        [System.Windows.Forms.Form]$Form
    )
    try {
        Do {
            $Form.Activate()
            [System.Windows.Forms.SendKeys]::SendWait("{BS}")
            [System.Windows.Forms.SendKeys]::SendWait(".")
            Start-Sleep -Milliseconds 180000  # 3 minutes
            
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
        
        Write-Log "Initializing keep-awake form..." "INFO"
        
        # Create and configure the form
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'SSH Keep-Awake'
        $form.Size = New-Object System.Drawing.Size(200,100)
        $form.StartPosition = 'Manual'
        $form.Location = New-Object System.Drawing.Point(1500,670)
        
        # Create and configure the textbox
        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.Size = New-Object System.Drawing.Size(200,100)
        $textBox.Multiline = $true
        
        # Add textbox to form
        $form.Controls.Add($textBox)
        $form.Topmost = $true
        
        # Show the form
        $form.Add_Shown({$textBox.Select()})
        $form.Show()
        
        Write-Log "Keep-awake form initialized" "INFO"
        
        # Start the keep-awake loop
        Start-Sleep -Milliseconds 1000
        Start-KeepAwake -Form $form
        
        # Cleanup
        $form.Close()
        Write-Log "Keep-awake form closed" "INFO"
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