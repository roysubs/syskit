#!/usr/bin/env pwsh
[CmdletBinding()]
param (
    [System.Net.IPAddress]$StartAddress,
    [System.Net.IPAddress]$EndAddress,
    [int]$MaxThreads = 100,
    [int]$Timeout = 1000
)

# --- 1. Range Generation (Handling your /22) ---
$allIPs = @()
if ($StartAddress -and $EndAddress) {
    # ... (Standard range logic)
} else {
    $interface = (netstat -rn | Select-String "default" | Select-Object -First 1 | ForEach-Object { ($_ -split '\s+')[3] })
    $config = ifconfig $interface
    if ($config -join ' ' -match 'inet\s+(\d+\.\d+\.\d+\.\d+)\s+netmask\s+0x([0-9a-fA-F]{8})') {
        $baseIP = [System.Net.IPAddress]$Matches[1]; $hexMask = $Matches[2]
        $binMask = [Convert]::ToString([Convert]::ToUInt32($hexMask, 16), 2).PadLeft(32, '0')
        $prefix = ($binMask -replace '0', '').Length
        $ipBytes = $baseIP.GetAddressBytes(); $mask = [uint32]::MaxValue -shl (32 - $prefix)
        $maskBytes = [System.BitConverter]::GetBytes($mask); if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($maskBytes) }
        $networkBytes = @(0,0,0,0); for ($i=0; $i -lt 4; $i++) { $networkBytes[$i] = $ipBytes[$i] -band $maskBytes[$i] }
        $startNum = [System.BitConverter]::ToUInt32((@($networkBytes[3], $networkBytes[2], $networkBytes[1], $networkBytes[0])), 0)
        for ($i = 1; $i -le ([Math]::Pow(2, (32 - $prefix)) - 2); $i++) {
            $cBytes = [System.BitConverter]::GetBytes([uint32]($startNum + $i))
            if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($cBytes) }
            $allIPs += ([System.Net.IPAddress]$cBytes).IPAddressToString
        }
    }
}

# --- 2. Parallel Ping ---
Write-Host "Scanning $($allIPs.Count) IPs..." -ForegroundColor Cyan
$activeIPs = $allIPs | ForEach-Object -Parallel {
    $ping = New-Object System.Net.NetworkInformation.Ping
    try { if ($ping.Send($_, $using:Timeout).Status -eq 'Success') { $_ } } finally { $ping.Dispose() }
} -ThrottleLimit $MaxThreads

# --- 3. The "Heavy Duty" Resolver ---
$myIp = (ifconfig | Select-String "inet " | ForEach-Object { $_.ToString().Split(' ')[1] })

$results = foreach ($ip in $activeIPs) {
    $name = $null

    # 1. Self Check
    if ($myIp -contains $ip) { $name = "$(hostname) (this mac)" }

    # 2. SMB/NetBIOS Probe (The winner for Windows/Linux)
    if (-not $name) {
        # Probing Port 137 (NetBIOS Name Service)
        $smb = smbutil lookup $ip 2>$null | Select-String "Got response from"
        if ($smb -match "from\s+(\S+)") { $name = $matches[1] }
    }

    # 3. DNS Lookup (Standard)
    if (-not $name) {
        try { 
            $dns = [System.Net.Dns]::GetHostEntry($ip)
            if ($dns.HostName -and $dns.HostName -ne $ip) { $name = $dns.HostName }
        } catch {}
    }

    # 4. mDNS / dscacheutil (Linux Avahi/Bonjour)
    if (-not $name) {
        $ds = dscacheutil -q host -a ip_address $ip
        if ($ds -match "name:\s+(\S+)") { $name = $matches[1] }
    }

    # 5. ARP Scrape
    if (-not $name) {
        $arp = arp -a | Select-String "\($ip\)"
        if ($arp -match '^(\S+)') { 
            $found = $matches[1]; if ($found -ne "?") { $name = "$found (arp)" } 
        }
    }

    [PSCustomObject]@{
        IP       = $ip
        Hostname = ($name ? $name : "Unknown")
    }
}

$results | Sort-Object { [version]$_.IP } | Format-Table -AutoSize
