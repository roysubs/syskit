#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Worker script for range-based pinging - macOS/Linux/Windows Compatible.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [System.Net.IPAddress]$StartAddress,

    [Parameter(Mandatory=$false)]
    [System.Net.IPAddress]$EndAddress,

    [string]$Subnet,
    [int]$MaxThreads = 100,
    [int]$Timeout = 1000  # Default to 1s (1000ms)
)

# --- IP Generation Logic ---
$allIPs = @()

if ($StartAddress -and $EndAddress) {
    # Generate IPs from Start to End
    $startBytes = $StartAddress.GetAddressBytes()
    $endBytes = $EndAddress.GetAddressBytes()
    if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($startBytes); [System.Array]::Reverse($endBytes) }
    
    $start = [System.BitConverter]::ToUInt32($startBytes, 0)
    $end = [System.BitConverter]::ToUInt32($endBytes, 0)

    for ($i = $start; $i -le $end; $i++) {
        $ipBytes = [System.BitConverter]::GetBytes($i)
        if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($ipBytes) }
        $allIPs += ([System.Net.IPAddress]$ipBytes).IPAddressToString
    }
}
elseif ($Subnet) {
    # Logic to handle CIDR (Simplified for brevity, assuming range is preferred)
    Write-Error "CIDR parsing not implemented in range-mode. Use Start/End parameters."
    exit 1
}

if ($allIPs.Count -eq 0) { Write-Error "No IPs to scan."; exit 1 }

# --- Scanning Logic (PS7 Optimized) ---
# We use ForEach-Object -Parallel because you are on a Mac with PWSH 7
$results = $allIPs | ForEach-Object -Parallel {
    $ip = $_
    $t = $using:Timeout
    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        $reply = $ping.Send($ip, $t)
        if ($reply.Status -eq 'Success') {
            # IMPORTANT: We return 'IPAddress' to match what ping-resolve.ps1 expects
            [PSCustomObject]@{
                IPAddress = [System.Net.IPAddress]$ip
                Status    = 'Online'
            }
        }
    } catch {} finally { $ping.Dispose() }
} -ThrottleLimit $MaxThreads

# Return the results to the calling script
return $results
