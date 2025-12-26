#!/usr/bin/env pwsh
<#
.SYNOPSIS
    High-performance network scanner - Cross-platform (macOS, Linux, Windows).

.DESCRIPTION
    Uses PowerShell 7's native parallel processing for maximum speed.
    Detects network settings automatically using:
    - macOS: ifconfig/netstat
    - Linux: ip addr
    - Windows: Get-NetIPConfiguration
#>
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
                NETWORK SCANNER - CROSS-PLATFORM OPTIMIZED
═══════════════════════════════════════════════════════════════════════════════
USAGE: ./ping-subnet.ps1 [OPTIONS]

PARAMETERS:
    -Subnet <CIDR>      Example: 192.168.1.0/24 (Auto-detected if omitted)
    -MaxThreads <Num>   Concurrent pings (Default: 100)
    -Timeout <Sec>      Ping timeout (Default: 1s)
    -IgnoreUnresolved   Only show hosts with DNS names
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
}

$startTime = Get-Date
$allIPs = @()

# --- Determine Network Range ---
if ($Subnet) {
    try {
        $ip, $prefixStr = $Subnet.Split('/')
        $baseIP = [System.Net.IPAddress]$ip
        $prefixLength = [int]$prefixStr
        Write-Host "Using manually specified subnet: $Subnet" -ForegroundColor Cyan
    } catch {
        Write-Error "Invalid CIDR format. Use e.g. 192.168.1.0/24"
        exit 1
    }
}
else {
    # Cross-Platform Auto-Detection
    try {
        if ($IsWindows) {
            Write-Host "Detected Windows - using Get-NetIPConfiguration..." -ForegroundColor Cyan
            $ipConfig = Get-NetIPConfiguration | Where-Object { 
                $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' 
            } | Select-Object -First 1
            
            $baseIP = [System.Net.IPAddress]$ipConfig.IPv4Address.IPAddress
            $prefixLength = $ipConfig.IPv4Address.PrefixLength
        }
        elseif ($IsMacOS) {
            Write-Host "Detected macOS - using ifconfig/netstat..." -ForegroundColor Cyan
            # Find the interface with the default route
            $interface = (netstat -rn | Select-String "default" | Select-Object -First 1 | ForEach-Object { ($_ -split '\s+')[3] })
            $config = ifconfig $interface
            
            if ($config -join ' ' -match 'inet\s+(\d+\.\d+\.\d+\.\d+)\s+netmask\s+0x([0-9a-fA-F]{8})') {
                $baseIP = [System.Net.IPAddress]$Matches[1]
                $hexMask = $Matches[2]
                $binMask = [Convert]::ToString([Convert]::ToUInt32($hexMask, 16), 2)
                $prefixLength = ($binMask -replace '0', '').Length
            } else { throw "Could not parse ifconfig for $interface" }
        }
        elseif ($IsLinux) {
            Write-Host "Detected Linux - using ip command..." -ForegroundColor Cyan
            $ipOutput = ip -4 -o addr show | Where-Object { $_ -match 'scope global' -and $_ -notmatch 'docker|virbr' } | Select-Object -First 1
            if ($ipOutput -match 'inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)') {
                $baseIP = [System.Net.IPAddress]$matches[1]
                $prefixLength = [int]$matches[2]
            } else { throw "Could not parse ip command output" }
        }
        
        Write-Host "Auto-detected: $($baseIP.IPAddressToString)/$prefixLength" -ForegroundColor Cyan
    }
    catch {
        Write-Error "Auto-detection failed: $($_.Exception.Message). Use -Subnet manually."
        exit 1
    }
}

# --- Calculate IP Range ---
try {
    $ipBytes = $baseIP.GetAddressBytes()
    $mask = [uint32]::MaxValue -shl (32 - $prefixLength)
    $maskBytes = [System.BitConverter]::GetBytes($mask)
    if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($maskBytes) }

    $networkBytes = @(0,0,0,0)
    for ($i=0; $i -lt 4; $i++) { $networkBytes[$i] = $ipBytes[$i] -band $maskBytes[$i] }
    
    $start = [System.BitConverter]::ToUInt32((@($networkBytes[3], $networkBytes[2], $networkBytes[1], $networkBytes[0])), 0)
    $count = [Math]::Pow(2, (32 - $prefixLength)) - 2

    for ($i = 1; $i -le $count; $i++) {
        $currentIPBytes = [System.BitConverter]::GetBytes([uint32]($start + $i))
        if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($currentIPBytes) }
        $allIPs += ([System.Net.IPAddress]$currentIPBytes).IPAddressToString
    }
    Write-Host "Scanning $($allIPs.Count) hosts..." -ForegroundColor Cyan
} catch {
    Write-Error "Range calculation failed: $($_.Exception.Message)"
    exit 1
}

# --- Scanning Logic ---
if ($isPS7) {
    $results = $allIPs | ForEach-Object -Parallel {
        $ip = $_
        if (Test-Connection -ComputerName $ip -Count 1 -TimeoutSeconds ($using:Timeout) -Quiet -ErrorAction SilentlyContinue) {
            $name = "N/A"
            try { $name = [System.Net.Dns]::GetHostEntry($ip).HostName } catch {}
            [PSCustomObject]@{ IP = $ip; Status = 'Online'; Hostname = $name }
        }
    } -ThrottleLimit $MaxThreads
} else {
    # Fallback for PS 5.1 (Sequential or simpler parallel)
    Write-Host "Running in legacy mode..." -ForegroundColor Yellow
    $results = foreach ($ip in $allIPs) {
        if (Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            [PSCustomObject]@{ IP = $ip; Status = 'Online'; Hostname = 'Scanning...' }
        }
    }
}

# --- Display Results ---
$elapsed = (Get-Date) - $startTime
Write-Host "`nScan Complete in $($elapsed.ToString('mm\:ss'))" -ForegroundColor Green
if ($results) {
    $out = $results | Sort-Object { [version]$_.IP }
    if ($IgnoreUnresolved) { $out = $out | Where-Object { $_.Hostname -ne "N/A" } }
    $out | Format-Table -AutoSize
} else {
    Write-Host "No active hosts found." -ForegroundColor Yellow
}
