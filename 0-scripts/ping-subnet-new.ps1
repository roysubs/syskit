#!/usr/bin/env pwsh
<#
.SYNOPSIS
    High-performance network scanner - OPTIMIZED for PowerShell 7 (Universal: Windows & Linux).

.DESCRIPTION
    Blazingly fast network scanner that uses PowerShell 7's native parallel processing
    (ForEach-Object -Parallel) for maximum speed, multi-protocol hostname resolution,
    and automatic active VPN detection / diagnostic guidance.
    
    Automatically detects the OS, network interface, default gateway, and any active VPNs.
    Works on Windows (PowerShell 5.1+) and Linux/macOS (PowerShell 7+).

.PARAMETER Subnet
    Optional. Manually specifies the target subnet in CIDR notation (e.g., "192.168.1.0/24").

.PARAMETER MaxThreads
    The maximum number of concurrent operations. Defaults to 100.

.PARAMETER Timeout
    Ping timeout in seconds. Defaults to 1 second.
    Lower values = faster scan but may miss slow-responding devices.
    Higher values = finds more devices but scan takes longer.

.PARAMETER IgnoreUnresolved
    If specified, hides hosts without resolved hostnames.
    By default, all active hosts are shown (including unresolved).

.PARAMETER Help
    Display detailed help information.

.EXAMPLE
    ./ping-subnet.ps1
    Auto-detects network and scans it quickly.

.EXAMPLE
    ./ping-subnet.ps1 -Subnet 192.168.1.0/24
    Scans the specified subnet.

.EXAMPLE
    ./ping-subnet.ps1 -MaxThreads 200 -Timeout 2
    Scans with 200 concurrent threads and 2-second timeout.

.EXAMPLE
    ./ping-subnet.ps1 -IgnoreUnresolved
    Shows only hosts with successfully resolved hostnames.
#>
#!/usr/bin/env pwsh
[CmdletBinding()]
param (
    [string]$Subnet,
    [int]$MaxThreads = 100,
    [int]$Timeout = 1,
    [switch]$IgnoreUnresolved,
    [Alias('h')]
    [switch]$Help
)

# --- Display Help ---
if ($Help) {
    Write-Host @"

═══════════════════════════════════════════════════════════════════════════════
                    NETWORK SCANNER - UNIVERSAL (PS7 / PS5)
═══════════════════════════════════════════════════════════════════════════════

DESCRIPTION:
    Ultra-fast network scanner optimized for PowerShell 7's native parallel
    processing with multi-protocol resolution (DNS, NetBIOS, ARP/Vendor) and
    VPN detection.

USAGE:
    ./ping-subnet.ps1 [OPTIONS]

PARAMETERS:

    -Subnet <CIDR>
        Manually specify the subnet to scan in CIDR notation.
        Example: -Subnet 192.168.1.0/24
        Default: Auto-detects your primary network interface

    -MaxThreads <NUMBER>
        Maximum concurrent operations (ThrottleLimit in PS7).
        Example: -MaxThreads 200
        Default: 100
        Range: 1-500 (recommended: 50-200)

    -Timeout <SECONDS>
        Ping timeout in seconds.
        Example: -Timeout 2
        Default: 1
        Range: 1-5

    -IgnoreUnresolved
        Hide hosts without resolved hostnames and only show resolved hosts.
        By default, all active hosts are displayed.

    -Help, -h
        Display this help message.

EXAMPLES:

    1. Basic scan (auto-detect network):
       ./ping-subnet.ps1

    2. Scan specific subnet:
       ./ping-subnet.ps1 -Subnet 10.0.0.0/24

    3. Fast scan with more threads:
       ./ping-subnet.ps1 -MaxThreads 200

    4. Complete scan (find slow devices):
       ./ping-subnet.ps1 -Timeout 3

    5. Show only hosts with resolved names:
       ./ping-subnet.ps1 -IgnoreUnresolved

═══════════════════════════════════════════════════════════════════════════════

"@ -ForegroundColor Cyan
    exit 0
}

# --- Check PowerShell Version ---
$isPS7 = $PSVersionTable.PSVersion.Major -ge 7

if ($isPS7) {
    Write-Host "✓ PowerShell 7+ detected - using native parallel processing" -ForegroundColor Green
} else {
    Write-Host "⚠ PowerShell $($PSVersionTable.PSVersion.Major) detected - performance will be reduced" -ForegroundColor Yellow
    Write-Host "  For best performance, install PowerShell 7: https://github.com/PowerShell/PowerShell" -ForegroundColor Yellow
}

# --- Start timing ---
$startTime = Get-Date

# --- Determine OS & Gateway ---
$isWindowsOS = ($PSVersionTable.PSVersion.Major -lt 6) -or ($PSVersionTable.Platform -eq 'Win32NT') -or $IsWindows
$gatewayIP = $null
$localHostIP = $null
$localHostName = [System.Net.Dns]::GetHostName()
$activeVpns = @()

# --- Detect Active VPNs ---
if ($isWindowsOS) {
    try {
        $vpnAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { 
            $_.Status -eq 'Up' -and (
                $_.InterfaceDescription -match 'WireGuard|TAP|TUN|Wintun|VPN|Tailscale|OpenVPN|Surfshark|Nord|Proton|Hamachi|ZeroTier|Radmin|Cisco|GlobalProtect|SonicWall' -or 
                $_.Name -match 'VPN|WireGuard|Tailscale|Radmin|Hamachi|Surfshark'
            )
        }
        if ($vpnAdapters) {
            $activeVpns = @($vpnAdapters | ForEach-Object { $_.Name } | Select-Object -Unique)
        }
    } catch {}
} elseif ($IsMacOS) {
    try {
        $currentIf = $null
        $vpnIfs = @()
        foreach ($line in (ifconfig -a 2>$null)) {
            if ($line -match '^(\S+):\s+flags=\S+<([^>]*)>') {
                $currentIf = $matches[1]
                $flags = $matches[2]
                if ($currentIf -match '^(utun|tun|tap|wg|ppp)' -and $flags -match 'UP' -and $flags -match 'RUNNING') {
                    $vpnIfs += $currentIf
                }
            }
        }
        $activeVpns = @($vpnIfs | Select-Object -Unique)
    } catch {}
} else {
    try {
        $tunLinks = ip -o link show 2>$null | Where-Object { $_ -match 'state UP' -and $_ -match 'tun|tap|wg|tailscale|nord|surfshark|proton' }
        if ($tunLinks) {
            $activeVpns = @($tunLinks | ForEach-Object { ($_ -split ':\s+')[1].Split('@')[0] } | Select-Object -Unique)
        }
    } catch {}
}

if ($activeVpns.Count -gt 0) {
    Write-Host "`n⚠ Active VPN detected: $($activeVpns -join ', ')" -ForegroundColor Yellow
    Write-Host "  • VPN tunnels redirect DNS queries to remote servers, preventing local (.home / .local) name resolution." -ForegroundColor DarkYellow
    Write-Host "  • Tip: Enable 'Allow LAN traffic / Bypass VPN on local network' in your VPN app, or disconnect VPN for full host discovery.`n" -ForegroundColor DarkYellow
}

# --- Determine Network Range ---
$allIPs = @()
if ($Subnet) {
    try {
        $ip, $prefixStr = $Subnet.Split('/')
        $baseIP = [System.Net.IPAddress]$ip
        $prefixLength = [int]$prefixStr
        Write-Host "Using manually specified subnet: $Subnet" -ForegroundColor Cyan
    }
    catch {
        Write-Error ("Invalid subnet format '{0}'. Please use CIDR notation (e.g., 192.168.1.0/24)." -f $Subnet)
        exit 1
    }
}
else {
    if ($isWindowsOS) {
        # Windows: Use Get-NetIPConfiguration
        Write-Host "Detected Windows - using Get-NetIPConfiguration..." -ForegroundColor Cyan
        try {
            $ipConfig = Get-NetIPConfiguration | Where-Object { 
                $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' -and $_.NetAdapter.InterfaceDescription -notmatch 'WireGuard|TAP|TUN|Wintun|VPN|Tailscale|Radmin'
            } | Select-Object -First 1
            
            # Fallback if primary physical adapter wasn't filtered
            if (-not $ipConfig) {
                $ipConfig = Get-NetIPConfiguration | Where-Object { 
                    $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' 
                } | Select-Object -First 1
            }
            
            if (-not $ipConfig) {
                Write-Error "Could not auto-detect the primary network on Windows. Specify a subnet manually with -Subnet."
                exit 1
            }
            
            $baseIP = [System.Net.IPAddress]$ipConfig.IPv4Address.IPAddress
            $prefixLength = $ipConfig.IPv4Address.PrefixLength
            $localHostIP = $baseIP.IPAddressToString
            if ($ipConfig.IPv4DefaultGateway) {
                $gatewayIP = $ipConfig.IPv4DefaultGateway.NextHop
            }
            Write-Host "Auto-detected network: $($baseIP.IPAddressToString)/$prefixLength" -ForegroundColor Cyan
        }
        catch {
            Write-Error "Error detecting Windows network: $($_.Exception.Message). Specify a subnet manually with -Subnet."
            exit 1
        }
    }
    elseif ($IsMacOS) {
        # macOS: Use ifconfig/netstat (no 'ip' command on macOS/BSD)
        Write-Host "Detected macOS - using ifconfig/netstat..." -ForegroundColor Cyan
        try {
            $defaultLine = netstat -rn | Select-String "^default" | Select-Object -First 1
            if (-not $defaultLine) {
                Write-Error "Could not find a default route. Specify a subnet manually with -Subnet."
                exit 1
            }
            $cols = ($defaultLine -split '\s+')
            $gatewayIP = $cols[1]
            $interface = $cols[3]

            $config = ifconfig $interface
            if (($config -join ' ') -match 'inet\s+(\d+\.\d+\.\d+\.\d+)\s+netmask\s+0x([0-9a-fA-F]{8})') {
                $baseIP = [System.Net.IPAddress]$matches[1]
                $hexMask = $matches[2]
                $binMask = [Convert]::ToString([Convert]::ToUInt32($hexMask, 16), 2).PadLeft(32, '0')
                $prefixLength = ($binMask -replace '0', '').Length
                $localHostIP = $matches[1]
                Write-Host "Auto-detected network: $($matches[1])/$prefixLength" -ForegroundColor Cyan
            }
            else {
                Write-Error "Could not parse ifconfig output for interface $interface. Specify a subnet manually with -Subnet."
                exit 1
            }
        }
        catch {
            Write-Error "Error detecting macOS network: $($_.Exception.Message). Specify a subnet manually with -Subnet."
            exit 1
        }
    }
    else {
        # Linux: Use 'ip' command
        Write-Host "Detected Linux - using ip command..." -ForegroundColor Cyan
        try {
            $ipOutput = ip -4 -o addr show | Where-Object {
                $_ -match 'scope global' -and $_ -notmatch 'docker|virbr|wg|tun|tailscale'
            } | Select-Object -First 1

            if (-not $ipOutput) {
                $ipOutput = ip -4 -o addr show | Where-Object {
                    $_ -match 'scope global' -and $_ -notmatch 'docker|virbr'
                } | Select-Object -First 1
            }

            if (-not $ipOutput) {
                Write-Error "Could not auto-detect the primary network interface. Specify a subnet manually with -Subnet."
                exit 1
            }

            if ($ipOutput -match 'inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)') {
                $baseIP = [System.Net.IPAddress]$matches[1]
                $prefixLength = [int]$matches[2]
                $localHostIP = $matches[1]
                Write-Host "Auto-detected network: $($matches[1])/$prefixLength" -ForegroundColor Cyan
            }
            else {
                Write-Error "Could not parse network information. Specify a subnet manually with -Subnet."
                exit 1
            }

            # Detect gateway on Linux
            $gwLine = ip route show default 2>$null | Select-Object -First 1
            if ($gwLine -match 'default via (\d+\.\d+\.\d+\.\d+)') {
                $gatewayIP = $matches[1]
            }
        }
        catch {
            Write-Error "Error detecting Linux network: $($_.Exception.Message). Specify a subnet manually with -Subnet."
            exit 1
        }
    }
}

# --- Calculate all IPs in the subnet ---
try {
    $ipAddressBytes = $baseIP.GetAddressBytes()
    $mask = [uint32]::MaxValue -shl (32 - $prefixLength)
    $subnetMaskBytes = [System.BitConverter]::GetBytes($mask)
    if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($subnetMaskBytes) }

    $networkAddressBytes = @(0,0,0,0)
    for ($i = 0; $i -lt 4; $i++) { $networkAddressBytes[$i] = $ipAddressBytes[$i] -band $subnetMaskBytes[$i] }
    $networkAddress = [System.Net.IPAddress]::new($networkAddressBytes)

    $invertedMaskBytes = $subnetMaskBytes | ForEach-Object { [byte]((-bnot $_) -band 0xFF) }
    $broadcastAddressBytes = @(0,0,0,0)
    for ($i = 0; $i -lt 4; $i++) { $broadcastAddressBytes[$i] = $networkAddressBytes[$i] -bor $invertedMaskBytes[$i] }

    $startBytes = $networkAddressBytes.Clone()
    $endBytes = $broadcastAddressBytes.Clone()

    if ([System.BitConverter]::IsLittleEndian) {
        [System.Array]::Reverse($startBytes)
        [System.Array]::Reverse($endBytes)
    }

    $start = [System.BitConverter]::ToUInt32($startBytes, 0)
    $end = [System.BitConverter]::ToUInt32($endBytes, 0)

    for ($i = ($start + 1); $i -lt $end; $i++) {
        $ipBytes = [System.BitConverter]::GetBytes($i)
        if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($ipBytes) }
        $allIPs += ([System.Net.IPAddress]$ipBytes).IPAddressToString
    }

    Write-Host "Scanning $($allIPs.Count) hosts in subnet $($networkAddress.IPAddressToString)/$prefixLength..." -ForegroundColor Cyan
    Write-Host "Using timeout: $($Timeout)s, Max threads: $MaxThreads" -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to calculate network range. Error: $($_.Exception.Message)"
    exit 1
}

# --- PowerShell 7: Use ForEach-Object -Parallel (FAST!) ---
if ($isPS7) {
    Write-Host "Starting parallel scan..." -ForegroundColor Cyan
    
    $results = $allIPs | ForEach-Object -Parallel {
        $ip = $_
        $timeoutSeconds = $using:Timeout
        $localIP = $using:localHostIP
        $localHost = $using:localHostName
        $gw = $using:gatewayIP
        
        # 1. Ping
        $pingSuccess = Test-Connection -ComputerName $ip -Count 1 -TimeoutSeconds $timeoutSeconds -Quiet -ErrorAction SilentlyContinue
        
        if ($pingSuccess) {
            $hostname = $null
            
            # Check if this is the scanning host
            if ($ip -eq $localIP) {
                $hostname = $localHost
            }
            
            # Fast DNS reverse lookup with strict timeout (prevents 5s hangs on VPN/unresolved)
            if (-not $hostname) {
                try {
                    $task = [System.Net.Dns]::GetHostEntryAsync($ip)
                    if ($task.Wait(350) -and $task.Result -and -not [string]::IsNullOrWhiteSpace($task.Result.HostName)) {
                        $hostname = $task.Result.HostName
                    }
                } catch {}
            }
            
            # NetBIOS Name Service (UDP 137) fallback for Windows/Samba hosts
            if (-not $hostname) {
                try {
                    $udp = [System.Net.Sockets.UdpClient]::new()
                    $udp.Client.ReceiveTimeout = 200
                    $udp.Client.SendTimeout = 200
                    $nbQuery = [byte[]]@(
                        0xA2, 0x48, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
                        0x00, 0x00, 0x00, 0x00, 0x20, 0x43, 0x4B, 0x41,
                        0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
                        0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
                        0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
                        0x41, 0x41, 0x41, 0x41, 0x41, 0x00, 0x00, 0x21,
                        0x00, 0x01
                    )
                    $udp.Connect($ip, 137)
                    [void]$udp.Send($nbQuery, $nbQuery.Length)
                    $ep = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
                    $resp = $udp.Receive([ref]$ep)
                    if ($resp.Length -ge 75) {
                        $name = [System.Text.Encoding]::ASCII.GetString($resp, 57, 15).Trim()
                        if ($name) { $hostname = $name }
                    }
                } catch {}
                finally {
                    if ($udp) { $udp.Dispose() }
                }
            }
            
            # Router / Gateway identification
            if (-not $hostname -and $gw -and $ip -eq $gw) {
                $hostname = "Router / Gateway"
            }
            
            if (-not $hostname) {
                $hostname = "N/A (Resolution Failed)"
            }
            
            [PSCustomObject]@{
                IP       = $ip
                Status   = 'Online'
                Hostname = $hostname
            }
        }
    } -ThrottleLimit $MaxThreads
}
# --- PowerShell 5.1: Use Runspaces (slower fallback) ---
else {
    Write-Host "Starting parallel scan using Runspaces..." -ForegroundColor Cyan
    
    $ScriptBlock = {
        param($ip, $timeoutMs, $localIP, $localHost, $gw)
        
        $ping = New-Object System.Net.NetworkInformation.Ping
        try {
            $reply = $ping.Send($ip, $timeoutMs)
            if ($reply.Status -eq 'Success') {
                $hostname = $null
                
                if ($ip -eq $localIP) {
                    $hostname = $localHost
                }
                
                if (-not $hostname) {
                    try {
                        $task = [System.Net.Dns]::GetHostEntryAsync($ip)
                        if ($task.Wait(350) -and $task.Result -and -not [string]::IsNullOrWhiteSpace($task.Result.HostName)) {
                            $hostname = $task.Result.HostName
                        }
                    } catch {}
                }
                
                if (-not $hostname -and $gw -and $ip -eq $gw) {
                    $hostname = "Router / Gateway"
                }
                
                if (-not $hostname) {
                    $hostname = "N/A (Resolution Failed)"
                }
                
                [PSCustomObject]@{
                    IP       = $ip
                    Status   = 'Online'
                    Hostname = $hostname
                }
            }
        }
        catch {}
        finally {
            $ping.Dispose()
        }
    }
    
    $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $MaxThreads)
    $RunspacePool.Open()
    
    $Jobs = @()
    foreach ($ip in $allIPs) {
        $ps = [PowerShell]::Create().AddScript($ScriptBlock).AddArgument($ip).AddArgument($Timeout * 1000).AddArgument($localHostIP).AddArgument($localHostName).AddArgument($gatewayIP)
        $ps.RunspacePool = $RunspacePool
        $Jobs += [PSCustomObject]@{
            PowerShell = $ps
            Handle = $ps.BeginInvoke()
        }
    }
    
    $results = @()
    foreach ($job in $Jobs) {
        $output = $job.PowerShell.EndInvoke($job.Handle)
        if ($output) {
            $results += $output
        }
        $job.PowerShell.Dispose()
    }
    
    $RunspacePool.Close()
    $RunspacePool.Dispose()
}

# --- Retrieve MAC Addresses & Vendors from ARP cache ---
$arpMap = @{}
$ouiMap = @{
    "90-9F-22" = "ASUSTek"; "D0-37-45" = "Dell"; "D8-9E-F3" = "Espressif (IoT)"
    "B8-27-EB" = "Raspberry Pi"; "DC-A6-32" = "Raspberry Pi"; "E4-5F-01" = "Raspberry Pi"
    "28-CD-C1" = "Raspberry Pi"; "00-11-32" = "Synology"; "00-08-9B" = "QNAP"
    "00-50-56" = "VMware"; "00-0C-29" = "VMware"; "00-15-5D" = "Hyper-V"
    "08-00-27" = "VirtualBox"; "F0-18-98" = "Apple"; "AC-BC-32" = "Apple"
    "3C-22-FB" = "Apple"; "40-9F-38" = "Apple"; "30-5A-3A" = "Google"
    "70-88-6B" = "Google"; "00-1A-11" = "Google"; "50-C7-BF" = "TP-Link"
    "E8-48-B8" = "TP-Link"; "98-DA-C4" = "Intel"; "80-86-F2" = "Intel"
    "F4-B8-5E" = "Samsung"; "94-E6-F7" = "Samsung"; "00-0C-E7" = "Amazon Echo"
}

try {
    if ($isWindowsOS) {
        Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { 
            $_.State -ne "Unreachable" -and $_.LinkLayerAddress -ne "00-00-00-00-00-00" 
        } | ForEach-Object {
            $arpMap[$_.IPAddress] = $_.LinkLayerAddress.ToUpper()
        }
    } elseif ($IsMacOS) {
        $arpLines = arp -a 2>$null
        foreach ($line in $arpLines) {
            if ($line -match '\((\d+\.\d+\.\d+\.\d+)\)\s+at\s+([0-9a-fA-F:]{17})') {
                $arpMap[$matches[1]] = ($matches[2] -replace ':', '-').ToUpper()
            }
        }
    } else {
        $arpLines = ip neigh show 2>$null
        foreach ($line in $arpLines) {
            if ($line -match '^(\d+\.\d+\.\d+\.\d+)\s+dev\s+\S+\s+lladdr\s+([0-9a-fA-F:]{17})') {
                $arpMap[$matches[1]] = ($matches[2] -replace ':', '-').ToUpper()
            }
        }
    }
} catch {}

# Enrich results with MAC / Device info
$enrichedResults = foreach ($item in $results) {
    $mac = $arpMap[$item.IP]
    $deviceInfo = ""
    if ($mac) {
        $prefix = ($mac.Split('-')[0..2] -join '-').ToUpper()
        if ($ouiMap.ContainsKey($prefix)) {
            $deviceInfo = $ouiMap[$prefix]
        } else {
            # Check for randomized/private MAC address (local bit set in first byte)
            try {
                $b0 = [Convert]::ToByte($mac.Substring(0,2), 16)
                if (($b0 -band 2) -eq 2) {
                    $deviceInfo = "Private/Random MAC (Phone/Tablet)"
                }
            } catch {}
        }
    }
    
    [PSCustomObject]@{
        IP       = $item.IP
        Status   = $item.Status
        Hostname = $item.Hostname
        MAC      = if ($mac) { $mac } else { "Local / Self" }
        Device   = $deviceInfo
    }
}

# --- Calculate elapsed time ---
$endTime = Get-Date
$elapsed = $endTime - $startTime
$elapsedFormatted = "{0:hh\:mm\:ss\.fff}" -f $elapsed

# --- Output Results ---
if ($enrichedResults) {
    $displayResults = $enrichedResults
    if ($IgnoreUnresolved) {
        $displayResults = $enrichedResults | Where-Object { $_.Hostname -ne "N/A (Resolution Failed)" }
    }
    
    Write-Host "`n===================================================" -ForegroundColor Green
    Write-Host "Scan Complete! Found $($enrichedResults.Count) active host(s)" -ForegroundColor Green
    if ($IgnoreUnresolved -and $displayResults.Count -lt $enrichedResults.Count) {
        Write-Host "Showing $($displayResults.Count) with resolved hostnames (use without -IgnoreUnresolved to see all)" -ForegroundColor Green
    }
    Write-Host "Note: Some mobile devices (Android/iOS) may appear intermittently due to sleep modes" -ForegroundColor Yellow
    Write-Host "Completed in: $elapsedFormatted" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Green
    
    if ($displayResults) {
        $displayResults | Sort-Object { 
            $octets = $_.IP.Split('.')
            [int]$octets[0] * 16777216 + [int]$octets[1] * 65536 + [int]$octets[2] * 256 + [int]$octets[3]
        } | Format-Table -AutoSize
    }
    else {
        Write-Host "All found hosts have unresolved hostnames. Run without -IgnoreUnresolved to see them." -ForegroundColor Yellow
    }
    
    # Check if unresolved hosts exist and VPN is active
    $unresolvedCount = ($enrichedResults | Where-Object { $_.Hostname -eq "N/A (Resolution Failed)" }).Count
    if ($unresolvedCount -gt 0 -and $activeVpns.Count -gt 0) {
        Write-Host "`nℹ $unresolvedCount host(s) could not resolve their local hostnames." -ForegroundColor Yellow
        Write-Host "  Because an active VPN/tunnel ($($activeVpns -join ', ')) is running, DNS may be routed through it instead of your LAN." -ForegroundColor DarkYellow
        Write-Host "  To resolve all names (e.g. .home/.local), enable 'Allow LAN traffic' in $($activeVpns[0]) or disconnect the VPN.`n" -ForegroundColor DarkYellow
    }
}
else {
    Write-Host "`n===================================================" -ForegroundColor Yellow
    Write-Host "Scan Complete. No active hosts found." -ForegroundColor Yellow
    Write-Host "Completed in: $elapsedFormatted" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Yellow
}

