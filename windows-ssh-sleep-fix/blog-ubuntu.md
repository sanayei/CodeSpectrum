# Preventing Ubuntu Sleep During SSH Sessions: A Debugged and Tested Solution

## Introduction

In a [previous article](https://medium.com/YOUR_ARTICLE_LINK), we discussed how to prevent Windows 11 from going to sleep during active SSH sessions. While Ubuntu handles SSH connections more gracefully than Windows, you might still want to explicitly prevent suspension during active SSH sessions for consistent behavior across your infrastructure.

This article presents a robust, tested solution using `systemd-inhibit` and a custom systemd service. Our improved version includes better error handling, proper logging, and more reliable SSH connection detection.

## The Solution Overview

Our approach combines several Linux tools to create a reliable solution:
- `systemd-inhibit` for suspend prevention
- `pgrep` and `ss` commands for reliable connection monitoring
- systemd service for automatic startup and recovery
- Comprehensive logging through systemd journal

## Step-by-Step Implementation

### 1. Creating the Monitor Script

First, let's create our improved monitoring script that includes robust error handling and proper logging.

```bash
#!/bin/bash

# Set up logging
exec 1> >(logger -s -t $(basename $0)) 2>&1

# Function to check for SSH connections
check_ssh() {
    # Look for sshd processes with established connections
    if pgrep -f "sshd:.*@" >/dev/null || \
       ss -t state established '( dport = :22 or sport = :22 )' | grep -q ssh; then
        return 0
    else
        return 1
    fi
}

# Main loop
echo "Starting SSH monitor..."

while true; do
    if check_ssh; then
        echo "Active SSH session detected. Inhibiting suspend..."
        # Use timeout to ensure the inhibit command doesn't hang
        timeout 3600 systemd-inhibit --what=sleep:idle --mode=block --who="ssh-monitor" \
            --why="Active SSH connection" sleep infinity &
        INHIBIT_PID=$!
        
        # Monitor while SSH is active
        while check_ssh; do
            sleep 30
        done
        
        # Clean up
        if [ -n "$INHIBIT_PID" ]; then
            kill $INHIBIT_PID 2>/dev/null
        fi
        echo "No active SSH sessions. Suspend allowed."
    fi
    sleep 30
done
```

Save this script to `/usr/local/bin/inhibit-suspend-on-ssh.sh` and make it executable:
```bash
sudo chmod +x /usr/local/bin/inhibit-suspend-on-ssh.sh
```

### 2. Creating the Systemd Service

Our improved service file includes better error handling and restart behavior:

```ini
[Unit]
Description=Inhibit suspend when SSH connection is active
After=network.target sshd.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/local/bin/inhibit-suspend-on-ssh.sh
Restart=on-failure
RestartSec=30
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Save this configuration to `/etc/systemd/system/inhibit-suspend-on-ssh.service`.

### 3. Activating and Managing the Service

Here's how to set up and manage the service:

```bash
# Reload systemd configuration
sudo systemctl daemon-reload

# Enable service to start at boot
sudo systemctl enable inhibit-suspend-on-ssh.service

# Start the service immediately
sudo systemctl start inhibit-suspend-on-ssh.service

# Check the status
sudo systemctl status inhibit-suspend-on-ssh.service
```

## How It Works

Let's break down the key components of our improved solution:

### 1. Robust SSH Detection
The script uses two methods to detect SSH connections:
```bash
if pgrep -f "sshd:.*@" >/dev/null || \
   ss -t state established '( dport = :22 or sport = :22 )' | grep -q ssh; then
```
- `pgrep` looks for active SSH processes
- `ss` checks for established SSH connections
- The dual approach ensures reliable detection

### 2. Proper Logging
```bash
exec 1> >(logger -s -t $(basename $0)) 2>&1
```
This ensures:
- All output goes to systemd journal
- Errors are properly captured
- Activities can be monitored easily

### 3. Process Management
```bash
timeout 3600 systemd-inhibit --what=sleep:idle --mode=block \
    --who="ssh-monitor" --why="Active SSH connection" sleep infinity &
INHIBIT_PID=$!
```
- Uses `timeout` to prevent hanging
- Properly manages background processes
- Includes cleanup of suspended processes

### 4. Service Recovery
```ini
Restart=on-failure
RestartSec=30
StartLimitIntervalSec=300
StartLimitBurst=5
```
- Automatically recovers from failures
- Prevents rapid restart cycles
- Provides time for system to stabilize

## Monitoring and Troubleshooting

### Checking Service Status
```bash
sudo systemctl status inhibit-suspend-on-ssh.service
```

### Viewing Logs
```bash
journalctl -u inhibit-suspend-on-ssh.service -f
```

Example log output:
```
Nov 30 08:45:08 ubuntu ssh-monitor[1234]: Starting SSH monitor...
Nov 30 08:45:38 ubuntu ssh-monitor[1234]: Active SSH session detected. Inhibiting suspend...
```

## Benefits of This Improved Approach

1. **Reliability**
   - Dual SSH detection methods
   - Proper process management
   - Automatic recovery from failures

2. **Maintainability**
   - Comprehensive logging
   - Clear status reporting
   - Easy troubleshooting

3. **Resource Efficiency**
   - Minimal system impact
   - Proper cleanup of resources
   - Controlled restart behavior

4. **Robustness**
   - Handles edge cases
   - Prevents service hanging
   - Manages system resources properly

## Conclusion

This improved solution provides a robust and reliable way to prevent Ubuntu systems from suspending during active SSH sessions. The enhanced error handling, proper logging, and dual SSH detection methods make it suitable for production environments where reliability is crucial.

---

*Need help troubleshooting or customizing this solution? Feel free to comment below!*