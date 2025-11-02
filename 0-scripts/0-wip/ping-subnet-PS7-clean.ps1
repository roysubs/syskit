#!/usr/bin/env pwsh
<#
.SYNOPSIS
    High-performance network scanner optimized for PowerShell 7+ (Cross-platform).

.DESCRIPTION
    Ultra-fast network scanner using PowerShell 7's native ForEach-Object -Parallel.
    Automatically detects your local network and finds all active hosts with
    superior mDNS/.home hostname resolution.
    
    Requires PowerShell 7 or later for best performance and DNS resolution.

.PARAMETER Subnet
    Optional. Manually specifies the target subnet in CIDR notation (e.g., "192.168.1.0/24").
    If not specified, auto-detects the primary network interface.

.PARAMETER Timeout
    Ping timeout in seconds. Defaults to 1 second.
    Range: 1-5 seconds.

.PARAMETER ThrottleLimit
    Maximum number of concurrent operations. Defaults to 100.
    Range: 1-500 (recommended: 50-200).

.PARAMETER ShowUnresolved
    If specified, displays all hosts including those with failed hostname resolution.
    By default, only hosts with resolved hostnames are shown.

.PARAMETER Help
    Display detailed help information.

.EXAMPLE
    ./ping-subnet-ps7.ps1
    Auto-detects network and scans it.

.EXAMPLE
    ./ping-subnet-ps7.ps1 -Subnet 192.168.1.0/24
    Scans the specified subnet.

.EXAMPLE
    ./ping-subnet-ps7.ps1 -Timeout 2 -ThrottleLimit 200
    Scans with 2-second timeout and 200 concurrent threads.

.EXAMPLE
    ./ping-subnet-ps7.ps1 -ShowUnresolved
    Shows all active hosts, including those without resolved hostnames.

.NOTES
    Requires: PowerShell 7+
    Check version: $PSVersionTable.PSVersion
    Install PS7: https://github.com/PowerShell/PowerShell
#>
[CmdletBinding()]
param (
    [string]$Subnet,
    [int]$Timeout = 1,
    [int]$ThrottleLimit = 100,
    [switch]$ShowUnresolved,
    [Alias('h')]
    [switch]$Help
)

# --- Display Help ---
if ($Help) {
    Write-Host @"

═══════════════════════════════════════════════════════════════════════════════
              NETWORK SCANNER - POWERSHELL 7+ OPTIMIZED
═══════════════════════════════════════════════════════════════════════════════

DESCRIPTION:
    Ultra-fast network scanner using PowerShell 7's native parallel processing.
    Provides superior mDNS/.home hostname resolution on all platforms.

USAGE:
    ./ping-subnet-ps7.ps1 [OPTIONS]

PARAMETERS:
    -Subnet <CIDR>         Subnet to scan (auto-detects if not specified)
    -Timeout <SECONDS>     Ping timeout (default: 1s, range: 1-5s)
    -ThrottleLimit <NUM>   Concurrent operations (default: 100, range: 1-500)
    -ShowUnresolved        Show all hosts including unresolved
    -Help, -h              Display this help

EXAMPLES:
    ./ping-subnet-ps7.ps1
    ./ping-subnet-ps7.ps1 -Subnet 192.168.1.0/24
    ./ping-subnet-ps7.ps1 -Timeout 2 -ThrottleLimit 200
    ./ping-subnet-ps7.ps1 -ShowUnresolved

PERFORMANCE:
    Typical scan time for /24 network (254 hosts): 5-10 seconds on all platforms!

REQUIREMENTS:
    PowerShell 7 or later required.
    Check version: `$PSVersionTable.PSVersion

═══════════════════════════════════════════════════════════════════════════════

"@ -ForegroundColor Cyan
    exit 0
}

# --- Check PowerShell Version ---
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error @"
This script requires PowerShell 7 or later for optimal performance.
Current version: $($PSVersionTable.PSVersion)

Install PowerShell 7: https://github.com/PowerShell/PowerShell

For PowerShell 5.1 support, use: ping-subnet-fast.ps1
"@
    exit 1
}

# --- Start timing ---
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# --- Determine Network Range ---
$allIPs = @()
if ($Subnet) {
    try {
        $ip, $prefixStr = $Subnet.Split('/')
        if (-not $prefixStr) { throw "Invalid CIDR format." }
        $baseIP = [System.Net.IPAddress]$ip
        $prefixLength = [int]$prefixStr
        Write-Host "Using specified subnet: $Subnet" -ForegroundColor Cyan
    }
    catch {
        Write-Error ("Invalid subnet format '{0}'. Please use CIDR notation (e.g., 192.168.1.0/24)." -f $Subnet)
        exit 1
    }
}
else {
    # Auto-detect network - works on both Windows and Linux with PS7
    Write-Host "Auto-detecting network..." -ForegroundColor Cyan
    
    # Try Windows method first
    $ipConfig = Get-NetIPConfiguration -ErrorAction SilentlyContinue | 
        Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } | 
        Select-Object -First 1
    
    if ($ipConfig) {
        $baseIP = [System.Net.IPAddress]($ipConfig.IPv4Address.IPAddress)
        $prefixLength = $ipConfig.IPv4Address.PrefixLength
        Write-Host "Detected network: $($baseIP.IPAddressToString)/$prefixLength" -ForegroundColor Cyan
    }
    else {
        # Linux/macOS fallback
        try {
            $ipOutput = ip -4 -o addr show 2>$null | 
                Where-Object { $_ -match 'scope global' -and $_ -notmatch 'docker|virbr' } | 
                Select-Object -First 1
            
            if ($ipOutput -match 'inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)') {
                $baseIP = [System.Net.IPAddress]$matches[1]
                $prefixLength = [int]$matches[2]
                Write-Host "Detected network: $($matches[1])/$prefixLength" -ForegroundColor Cyan
            }
            else {
                throw "Could not parse network information"
            }
        }
        catch {
            Write-Error "Could not auto-detect network. Please specify -Subnet manually."
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

    $networkAddressBytes = for ($i = 0; $i -lt 4; $i++) { $ipAddressBytes[$i] -band $subnetMaskBytes[$i] }
    $networkAddress = [System.Net.IPAddress]::new($networkAddressBytes)

    $invertedMaskBytes = $subnetMaskBytes | ForEach-Object { [byte]((-bnot $_) -band 0xFF) }
    $broadcastAddressBytes = for ($i = 0; $i -lt 4; $i++) { $networkAddressBytes[$i] -bor $invertedMaskBytes[$i] }

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
        $allIPs += ([System.Net.IPAddress]$ipBytes).ToString()
    }

    Write-Host "Scanning $($allIPs.Count) hosts in subnet $($networkAddress.IPAddressToString)/$prefixLength..." -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to calculate network range. Error: $($_.Exception.Message)"
    exit 1
}

# --- PowerShell 7 Parallel Scan (FAST!) ---
$results = $allIPs | ForEach-Object -Parallel {
    $ip = $_
    $timeoutSeconds = $using:Timeout
    
    # Test-Connection with TimeoutSeconds is a PS7 feature
    $pingSuccess = Test-Connection -ComputerName $ip -Count 1 -TimeoutSeconds $timeoutSeconds -Quiet -ErrorAction SilentlyContinue
    
    if ($pingSuccess) {
        $hostname = "N/A (Resolution Failed)"
        try {
            # PS7 has much better DNS resolution, especially for mDNS/.home
            $dns = [System.Net.Dns]::GetHostEntry($ip)
            if ($dns -and -not [string]::IsNullOrWhiteSpace($dns.HostName)) {
                $hostname = $dns.HostName
            }
        }
        catch {
            # Expected if no reverse DNS record exists
        }
        
        [PSCustomObject]@{
            IP       = $ip
            Status   = 'Online'
            Hostname = $hostname
        }
    }
} -ThrottleLimit $ThrottleLimit

# --- Stop timing ---
$Stopwatch.Stop()

# --- Output Results ---
if ($results) {
    # Filter out unresolved hostnames unless ShowUnresolved is specified
    $displayResults = $results
    if (-not $ShowUnresolved) {
        $displayResults = $results | Where-Object { $_.Hostname -ne "N/A (Resolution Failed)" }
    }
    
    Write-Host "`n===================================================" -ForegroundColor Green
    Write-Host "Scan Complete! Found $($results.Count) active host(s)" -ForegroundColor Green
    if (-not $ShowUnresolved) {
        Write-Host "Showing $($displayResults.Count) with resolved hostnames (use -ShowUnresolved to see all)" -ForegroundColor Green
    }
    Write-Host "Completed in: $($Stopwatch.Elapsed.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Green
    
    if ($displayResults) {
        $displayResults | Sort-Object { [System.Version]$_.IP } | Format-Table -AutoSize
    }
    else {
        Write-Host "`nNo hosts with resolved hostnames found. Use -ShowUnresolved to see all active IPs." -ForegroundColor Yellow
    }
}
else {
    Write-Host "`n===================================================" -ForegroundColor Yellow
    Write-Host "Scan Complete. No active hosts found." -ForegroundColor Yellow
    Write-Host "Completed in: $($Stopwatch.Elapsed.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Yellow
}
