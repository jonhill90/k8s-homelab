# Port Forwarding Configuration

Windows port forwarding configuration for Mac workstation access to WSL2 Kubernetes cluster.

## Overview

WSL2 uses NAT networking, which means external devices (like Mac workstations) cannot directly access services running in WSL2. Windows port forwarding bridges this gap by forwarding ports from the Windows host to WSL2.

**Important:** This script is configured for Arch Linux WSL2 distribution (`archlinux`). If you're using a different distribution (e.g., Ubuntu, Debian), you'll need to modify the `wsl -d archlinux` commands in the script to match your distribution name.

## Network Architecture

```
Mac (10.0.0.x)
    ↓
Windows Host (10.0.0.y)
    ↓ Port Forwarding
WSL2 (172.x.x.x - dynamic)
    ↓
kind Cluster
```

## Port Forwarding Script

**Location:** `C:\Scripts\wsl-port-forward.ps1`

**Purpose:**
- Automatically detects WSL2 IP address (changes on reboot)
- Creates Windows port forwarding rules
- Logs all operations to transcript file
- Forwards ports: 2222 (SSH), 80 (HTTP), 443 (HTTPS), 6443 (K8s API)

## Script Contents

```powershell
# WSL2 Port Forwarding Script
# Location: C:\Scripts\wsl-port-forward.ps1
# Run as Administrator

Start-Transcript -Path "C:\Scripts\wsl-port-forward.log" -Append

Write-Host "Starting port forward script at $(Get-Date)..."
Start-Sleep -Seconds 5

Write-Host "Ensuring WSL is running..."
$wsl_start = wsl -d archlinux echo "WSL started" 2>&1
Write-Host "WSL start output: $wsl_start"
Start-Sleep -Seconds 3

Write-Host "Getting WSL IP..."
$ip_output = wsl -d archlinux ip addr show eth0 2>&1 | Out-String
Write-Host "Raw ip output: $ip_output"

# Parse IP address more reliably
$ip_lines = $ip_output -split "`n"
$inet_line = $ip_lines | Where-Object { $_ -match '^\s*inet\s+(\d+\.\d+\.\d+\.\d+)' }
Write-Host "Inet line: $inet_line"

if ($null -eq $inet_line -or $inet_line.Count -eq 0) {
    Write-Host "ERROR: No inet line found"
    Stop-Transcript
    exit 1
}

# Extract IP using regex
if ($inet_line -match '(\d+\.\d+\.\d+\.\d+)') {
    $wsl_ip = $Matches[1]
    Write-Host "Extracted WSL IP: $wsl_ip"
} else {
    Write-Host "ERROR: Failed to extract IP from line"
    Stop-Transcript
    exit 1
}

if ([string]::IsNullOrEmpty($wsl_ip)) {
    Write-Host "ERROR: IP is empty"
    Stop-Transcript
    exit 1
}

Write-Host "Deleting old port forwarding rules..."
@(2222, 80, 443, 6443) | ForEach-Object {
    netsh interface portproxy delete v4tov4 listenport=$_ listenaddress=0.0.0.0 2>&1 | Out-Null
}

Write-Host "Adding port forwarding rules to $wsl_ip..."
@{2222='SSH'; 80='HTTP'; 443='HTTPS'; 6443='K8s API'}.GetEnumerator() | ForEach-Object {
    Write-Host "Adding $($_.Value) port forwarding (port $($_.Key))..."
    netsh interface portproxy add v4tov4 listenport=$($_.Key) listenaddress=0.0.0.0 connectport=$($_.Key) connectaddress=$wsl_ip 2>&1
}

Write-Host "Current port forwarding rules:"
netsh interface portproxy show all

Write-Host "Script completed successfully at $(Get-Date)"
Stop-Transcript
```

## Installation

### Step 1: Create Script File

```powershell
# Run as Administrator
# Create directory if it doesn't exist
New-Item -ItemType Directory -Path C:\Scripts -Force

# Create script file
# Copy contents from above into C:\Scripts\wsl-port-forward.ps1
notepad C:\Scripts\wsl-port-forward.ps1
```

### Step 2: Run Script

```powershell
# Run as Administrator
C:\Scripts\wsl-port-forward.ps1
```

**Expected Output:**
```
Transcript started, output file is C:\Scripts\wsl-port-forward.log
Starting port forward script at 01/29/2025 10:15:30...
Ensuring WSL is running...
WSL start output: WSL started
Getting WSL IP...
Raw ip output: 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:15:5d:xx:xx:xx brd ff:ff:ff:ff:ff:ff
    inet 172.28.240.123/20 brd 172.28.255.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::xxxx:xxxx:xxxx:xxxx/64 scope link
       valid_lft forever preferred_lft forever

Inet line:     inet 172.28.240.123/20 brd 172.28.255.255 scope global eth0
Extracted WSL IP: 172.28.240.123
Deleting old port forwarding rules...
Adding port forwarding rules to 172.28.240.123...
Adding SSH port forwarding (port 2222)...
Adding HTTP port forwarding (port 80)...
Adding HTTPS port forwarding (port 443)...
Adding K8s API port forwarding (port 6443)...
Current port forwarding rules:

Listen on ipv4:             Connect to ipv4:

Address         Port        Address         Port
--------------- ----------  --------------- ----------
0.0.0.0         2222        172.28.240.123  2222
0.0.0.0         80          172.28.240.123  80
0.0.0.0         443         172.28.240.123  443
0.0.0.0         6443        172.28.240.123  6443

Script completed successfully at 01/29/2025 10:15:35
```

### Step 3: Verify Forwarding

**From Windows:**
```powershell
# Check forwarding rules
netsh interface portproxy show all

# Get WSL2 IP and test connectivity
$wsl_ip = (wsl -d archlinux ip addr show eth0 | Select-String -Pattern 'inet\s+(\d+\.\d+\.\d+\.\d+)' | ForEach-Object { $_.Matches.Groups[1].Value })
Test-NetConnection -ComputerName $wsl_ip -Port 6443

# Check transcript log
Get-Content C:\Scripts\wsl-port-forward.log -Tail 20
```

**From Mac:**
```bash
# Test connectivity to Windows host
nc -zv <windows-ip> 6443
# Connection to <windows-ip> port 6443 [tcp/sun-sr-https] succeeded!

# Test kubectl
kubectl get nodes
```

## Automatic Startup

### Option 1: Task Scheduler

```powershell
# Create scheduled task to run on startup
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Scripts\wsl-port-forward.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "WSL2 Port Forwarding" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Forward ports to WSL2 for Kubernetes cluster access"
```

### Option 2: Startup Folder (Requires UAC Prompt)

```powershell
# Create shortcut in Startup folder
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\wsl-port-forward.lnk")
$Shortcut.TargetPath = "PowerShell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -File C:\Scripts\wsl-port-forward.ps1"
$Shortcut.WorkingDirectory = "C:\Scripts"
$Shortcut.Description = "WSL2 Port Forwarding"
$Shortcut.Save()

# Note: Will prompt for admin on every startup
```

## Troubleshooting

### Port forwarding not working

**Check WSL2 is running:**
```powershell
wsl --list --verbose
# STATE should be "Running"
```

**Check WSL2 IP:**
```powershell
wsl -d archlinux ip addr show eth0
# Should show inet line like: inet 172.x.x.x/20

# Or extract just the IP:
wsl -d archlinux ip addr show eth0 | Select-String -Pattern 'inet\s+(\d+\.\d+\.\d+\.\d+)' | ForEach-Object { $_.Matches.Groups[1].Value }
```

**Re-run script:**
```powershell
C:\Scripts\wsl-port-forward.ps1
```

**Check script log:**
```powershell
# View full log
Get-Content C:\Scripts\wsl-port-forward.log

# View last 50 lines
Get-Content C:\Scripts\wsl-port-forward.log -Tail 50
```

### Firewall blocking connections

**Note:** The current script does not automatically configure Windows Firewall rules. If you experience connectivity issues from external devices, you may need to manually configure firewall rules.

**Check firewall rules:**
```powershell
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "WSL2*" }
```

**Manually add rules (if needed):**
```powershell
# Run as Administrator
New-NetFirewallRule -DisplayName "WSL2 SSH" -Direction Inbound -LocalPort 2222 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WSL2 HTTP" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WSL2 HTTPS" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WSL2 Kubernetes API" -Direction Inbound -LocalPort 6443 -Protocol TCP -Action Allow
```

**Remove firewall rules:**
```powershell
Remove-NetFirewallRule -DisplayName "WSL2 SSH" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "WSL2 HTTP" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "WSL2 HTTPS" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "WSL2 Kubernetes API" -ErrorAction SilentlyContinue
```

### WSL2 IP changes after reboot

**This is normal behavior.** WSL2 gets a new IP address on every Windows reboot.

**Solutions:**
1. Run `wsl-port-forward.ps1` after every reboot
2. Set up automatic startup (Task Scheduler)
3. WSL2 IP is detected automatically by the script

### Mac can't connect to Windows

**Check Windows IP:**
```powershell
ipconfig | findstr IPv4
```

**Check Windows firewall:**
```powershell
# Disable Windows Firewall temporarily to test
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# Test from Mac
nc -zv <windows-ip> 6443

# Re-enable if it works
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
```

**Check network connectivity:**
```bash
# From Mac
ping <windows-ip>
```

## Port Forwarding Status

**Check current rules:**
```powershell
netsh interface portproxy show all
```

**Check listening ports:**
```powershell
netstat -an | findstr "LISTENING" | findstr "80\|443\|6443"
```

**Check connections:**
```powershell
netstat -an | findstr "ESTABLISHED" | findstr "6443"
```

## Removing Port Forwarding

**Remove all rules:**
```powershell
netsh interface portproxy reset
```

**Remove specific rule:**
```powershell
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=6443
```

**Remove firewall rules (if previously created):**
```powershell
Remove-NetFirewallRule -DisplayName "WSL2 SSH" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "WSL2 HTTP" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "WSL2 HTTPS" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "WSL2 Kubernetes API" -ErrorAction SilentlyContinue
```

## Advanced Configuration

### Forward Additional Ports

```powershell
# Method 1: Add to deletion array in script (line 43)
@(2222, 80, 443, 6443, 8080, 9090) | ForEach-Object {
    netsh interface portproxy delete v4tov4 listenport=$_ listenaddress=0.0.0.0 2>&1 | Out-Null
}

# Method 2: Add to forwarding hashtable in script (line 48)
@{2222='SSH'; 80='HTTP'; 443='HTTPS'; 6443='K8s API'; 8080='Custom'; 9090='Prometheus'}.GetEnumerator() | ForEach-Object {
    Write-Host "Adding $($_.Value) port forwarding (port $($_.Key))..."
    netsh interface portproxy add v4tov4 listenport=$($_.Key) listenaddress=0.0.0.0 connectport=$($_.Key) connectaddress=$wsl_ip 2>&1
}

# Method 3: Manually add a single port
$wsl_ip = (wsl -d archlinux ip addr show eth0 | Select-String -Pattern 'inet\s+(\d+\.\d+\.\d+\.\d+)' | ForEach-Object { $_.Matches.Groups[1].Value })
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=8080 connectaddress=$wsl_ip connectport=8080
```

### Limit to Specific IP

```powershell
# Instead of 0.0.0.0 (all IPs), use specific IP
netsh interface portproxy add v4tov4 listenaddress=192.168.1.100 listenport=6443 connectaddress=$wslIp connectport=6443

# Only Mac at 192.168.1.100 can connect
```

### IPv6 Support

```powershell
# Forward IPv6
netsh interface portproxy add v6tov4 listenaddress=:: listenport=6443 connectaddress=$wslIp connectport=6443
```

## Reference

**Official Documentation:**
- [WSL2 Networking](https://docs.microsoft.com/en-us/windows/wsl/networking)
- [netsh interface portproxy](https://docs.microsoft.com/en-us/windows-server/networking/technologies/netsh/netsh-interface-portproxy)

**Related Scripts:**
- Current script location: `C:\Scripts\wsl-port-forward.ps1`
- Cluster setup: `~/k8s-homelab/scripts/01-setup-cluster.sh`

**Network Flow:**
```
Mac kubectl (10.0.0.x:random)
    → Windows (10.0.0.y:6443)
    → WSL2 (172.x.x.x:6443)
    → kind control-plane (0.0.0.0:6443)
    → Kubernetes API Server
```