# Port Forwarding Configuration

Windows port forwarding configuration for Mac workstation access to WSL2 Kubernetes cluster.

## Overview

WSL2 uses NAT networking, which means external devices (like Mac workstations) cannot directly access services running in WSL2. Windows port forwarding bridges this gap by forwarding ports from the Windows host to WSL2.

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
- Configures Windows Firewall rules
- Forwards ports: 80, 443, 6443

## Script Contents

```powershell
# WSL2 Port Forwarding Script
# Location: C:\Scripts\wsl-port-forward.ps1
# Run as Administrator

# Get WSL2 IP address
$wslIp = (wsl hostname -I).Trim()

if ([string]::IsNullOrEmpty($wslIp)) {
    Write-Host "ERROR: Could not detect WSL2 IP address" -ForegroundColor Red
    Write-Host "Ensure WSL2 is running: wsl --list --verbose" -ForegroundColor Yellow
    exit 1
}

Write-Host "Detected WSL2 IP: $wslIp" -ForegroundColor Green

# Ports to forward
$ports = @(80, 443, 6443)

# Remove existing forwarding rules
Write-Host "Removing old port forwarding rules..." -ForegroundColor Yellow
netsh interface portproxy reset

# Create new forwarding rules
foreach ($port in $ports) {
    Write-Host "Forwarding port $port to WSL2..." -ForegroundColor Cyan
    netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$port connectaddress=$wslIp connectport=$port
}

# Configure Windows Firewall
Write-Host "Configuring Windows Firewall..." -ForegroundColor Cyan

# Remove old rules
Remove-NetFirewallRule -DisplayName "WSL2 HTTP" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "WSL2 HTTPS" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "WSL2 Kubernetes API" -ErrorAction SilentlyContinue

# Add new rules
New-NetFirewallRule -DisplayName "WSL2 HTTP" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow | Out-Null
New-NetFirewallRule -DisplayName "WSL2 HTTPS" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow | Out-Null
New-NetFirewallRule -DisplayName "WSL2 Kubernetes API" -Direction Inbound -LocalPort 6443 -Protocol TCP -Action Allow | Out-Null

Write-Host "`nPort forwarding configured successfully!" -ForegroundColor Green
Write-Host "Current forwarding rules:" -ForegroundColor Yellow
netsh interface portproxy show all

Write-Host "`nFirewall rules:" -ForegroundColor Yellow
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "WSL2*" } | Select-Object DisplayName, Enabled, Direction, Action
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
Detected WSL2 IP: 172.28.240.123
Removing old port forwarding rules...
Forwarding port 80 to WSL2...
Forwarding port 443 to WSL2...
Forwarding port 6443 to WSL2...
Configuring Windows Firewall...

Port forwarding configured successfully!
Current forwarding rules:
Listen on ipv4:             Connect to ipv4:
Address         Port        Address         Port
--------------- ----------  --------------- ----------
0.0.0.0         80          172.28.240.123  80
0.0.0.0         443         172.28.240.123  443
0.0.0.0         6443        172.28.240.123  6443
```

### Step 3: Verify Forwarding

**From Windows:**
```powershell
# Check forwarding rules
netsh interface portproxy show all

# Test WSL2 connectivity
Test-NetConnection -ComputerName (wsl hostname -I).Trim() -Port 6443
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
wsl hostname -I
# Should return IP like 172.x.x.x
```

**Re-run script:**
```powershell
C:\Scripts\wsl-port-forward.ps1
```

### Firewall blocking connections

**Check firewall rules:**
```powershell
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "WSL2*" }
```

**Manually add rules:**
```powershell
New-NetFirewallRule -DisplayName "WSL2 HTTP" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WSL2 HTTPS" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WSL2 Kubernetes API" -Direction Inbound -LocalPort 6443 -Protocol TCP -Action Allow
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

**Remove firewall rules:**
```powershell
Remove-NetFirewallRule -DisplayName "WSL2 HTTP"
Remove-NetFirewallRule -DisplayName "WSL2 HTTPS"
Remove-NetFirewallRule -DisplayName "WSL2 Kubernetes API"
```

## Advanced Configuration

### Forward Additional Ports

```powershell
# Add to $ports array in script
$ports = @(80, 443, 6443, 8080, 9090)  # Add custom ports

# Or manually:
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=8080 connectaddress=$wslIp connectport=8080
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