<#
.SYNOPSIS
    Scans the local network to find active hosts and resolve their hostnames using PowerShell 5.1-compatible parallelism.

.DESCRIPTION
    A self-contained script that uses Runspaces to achieve high-speed, parallel network scanning on systems running PowerShell 5.1. It determines the local network range automatically or accepts a manually specified subnet.

.PARAMETER Subnet
    Optional. Manually specifies the target subnet in CIDR notation (e.g., "192.168.1.0/24").

.PARAMETER MaxThreads
    The maximum number of concurrent pings. Defaults to 50.
#>
[CmdletBinding()]
param (
    [string]$Subnet,
    [int]$MaxThreads = 50
)

# --- Define the work to be done by each thread ---
# This script block takes an IP address, pings it, and resolves the hostname if online.
$ScriptBlock = {
    param($ip)

    $pingSuccess = Test-Connection -ComputerName $ip -Count 1 -ErrorAction SilentlyContinue

    if ($pingSuccess) {
        $hostname = "N/A (Resolution Failed)"
        try {
            $dns = [System.Net.Dns]::GetHostEntry($ip)
            if ($dns -and -not [string]::IsNullOrWhiteSpace($dns.HostName)) {
                $hostname = $dns.HostName
            }
        }
        catch {
            # Expected if no reverse DNS record exists
        }

        # Output a result object
        return [PSCustomObject]@{
            IP       = $ip
            Status   = 'Online'
            Hostname = $hostname
        }
    }
    # Return nothing if the host is offline
}

# --- Determine Network Range (Identical logic to the PS7 script) ---
$allIPs = @()
if ($Subnet) {
    try {
        $ip, $prefixStr = $Subnet.Split('/')
        $baseIP = [System.Net.IPAddress]$ip
        $prefixLength = [int]$prefixStr
    }
    catch {
        Write-Error ("Invalid subnet format '{0}'. Please use CIDR notation (e.g., 192.168.1.0/24)." -f $Subnet)
        exit 1
    }
}
else {
    $ipConfig = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
    if (-not $ipConfig) {
        Write-Error "Could not auto-detect the primary network. Specify a subnet manually with -Subnet."
        exit 1
    }
    $baseIP = $ipConfig.IPv4Address.IPAddress
    $prefixLength = $ipConfig.IPv4Address.PrefixLength
}

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
}
catch {
    Write-Error "Failed to calculate network range. Error: $($_.Exception.Message)"
    exit 1
}

# --- Setup and run the parallel jobs ---
# 1. Create a "Runspace Pool" (the team of workers)
$RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $MaxThreads)
$RunspacePool.Open()

$Jobs = @()
$Results = @()

# 2. Assign a job to a worker for each IP address
foreach ($ip in $allIPs) {
    $ps = [PowerShell]::Create().AddScript($ScriptBlock).AddArgument($ip)
    $ps.RunspacePool = $RunspacePool
    $Jobs += $ps.BeginInvoke()
}

Write-Host "All jobs submitted. Waiting for results..."

# 3. Collect the results from all workers
foreach ($job in $Jobs) {
    $result = $job.AsyncWaitHandle.WaitOne()
    $output = $job.PowerShell.EndInvoke($job)
    if ($output) {
        $Results += $output
    }
}

$RunspacePool.Close()

# --- Output Results ---
if ($Results) {
    Write-Host "`nScan Complete. Found $($Results.Count) active host(s):" -ForegroundColor Green
    $Results | Sort-Object { [System.Version]$_.IP } | Format-Table -AutoSize
}
else {
    Write-Host "`nScan Complete. No active hosts found." -ForegroundColor Yellow
}
