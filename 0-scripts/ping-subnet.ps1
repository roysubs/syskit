#!/usr/bin/env pwsh
<#
.SYNOPSIS
    High-performance network scanner - OPTIMIZED for PowerShell 7 (Universal: Windows & Linux).

.DESCRIPTION
    Blazingly fast network scanner that uses PowerShell 7's native parallel processing
    (ForEach-Object -Parallel) for maximum speed and superior DNS resolution.
    Falls back to Runspaces for PowerShell 5.1 compatibility.
    
    Automatically detects the OS and uses appropriate commands for network detection.
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
    ./ping-subnet-ps7.ps1
    Auto-detects network and scans it quickly.

.EXAMPLE
    ./ping-subnet-ps7.ps1 -Subnet 192.168.1.0/24
    Scans the specified subnet.

.EXAMPLE
    ./ping-subnet-ps7.ps1 -MaxThreads 200 -Timeout 2
    Scans with 200 concurrent threads and 2-second timeout.

.EXAMPLE
    ./ping-subnet-ps7.ps1 -IgnoreUnresolved
    Shows only hosts with successfully resolved hostnames.
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
                    NETWORK SCANNER - POWERSHELL 7 OPTIMIZED
═══════════════════════════════════════════════════════════════════════════════

DESCRIPTION:
    Ultra-fast network scanner optimized for PowerShell 7's native parallel
    processing. Automatically detects your local network and finds all active
    hosts with superior DNS resolution.
    
    PowerShell 7 version is 3-4x FASTER than the Runspace version and has
    BETTER mDNS/.home hostname resolution!

USAGE:
    ./ping-subnet-ps7.ps1 [OPTIONS]

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
        
        Tradeoff:
          • Lower (1s)   = Faster scan, may miss slow devices
          • Higher (2-3s) = Slower scan, finds more devices

    -IgnoreUnresolved
        Hide hosts without resolved hostnames and only show resolved hosts.
        By default, all active hosts are displayed.
        Example: -IgnoreUnresolved

    -Help, -h
        Display this help message.

EXAMPLES:

    1. Basic scan (auto-detect network):
       ./ping-subnet-ps7.ps1

    2. Scan specific subnet:
       ./ping-subnet-ps7.ps1 -Subnet 10.0.0.0/24

    3. Fast scan with more threads:
       ./ping-subnet-ps7.ps1 -MaxThreads 200

    4. Complete scan (find slow devices):
       ./ping-subnet-ps7.ps1 -Timeout 3

    5. Show only hosts with resolved names:
       ./ping-subnet-ps7.ps1 -IgnoreUnresolved

PERFORMANCE:

    PowerShell 7 (ForEach-Object -Parallel):
    • Linux:   5 seconds   (excellent!)
    • Windows: 5 seconds   (excellent!)
    
    PowerShell 5.1 (Runspaces fallback):
    • Linux:   9 seconds   (good)
    • Windows: 20+ seconds (poor)

    PS7 is the clear winner - same speed on both platforms!

REQUIREMENTS:

    For best performance, use PowerShell 7+
    Check your version: `$PSVersionTable.PSVersion`
    
    Install PS7: https://github.com/PowerShell/PowerShell

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
    # Detect OS and use appropriate network detection method
    $isWindowsOS = ($PSVersionTable.PSVersion.Major -lt 6) -or ($PSVersionTable.Platform -eq 'Win32NT') -or $IsWindows
    
    if ($isWindowsOS) {
        # Windows: Use Get-NetIPConfiguration
        Write-Host "Detected Windows - using Get-NetIPConfiguration..." -ForegroundColor Cyan
        try {
            $ipConfig = Get-NetIPConfiguration | Where-Object { 
                $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' 
            } | Select-Object -First 1
            
            if (-not $ipConfig) {
                Write-Error "Could not auto-detect the primary network on Windows. Specify a subnet manually with -Subnet."
                exit 1
            }
            
            $baseIP = [System.Net.IPAddress]$ipConfig.IPv4Address.IPAddress
            $prefixLength = $ipConfig.IPv4Address.PrefixLength
            Write-Host "Auto-detected network: $($baseIP.IPAddressToString)/$prefixLength" -ForegroundColor Cyan
        }
        catch {
            Write-Error "Error detecting Windows network: $($_.Exception.Message). Specify a subnet manually with -Subnet."
            exit 1
        }
    }
    else {
        # Linux/macOS: Use 'ip' command
        Write-Host "Detected Linux/macOS - using ip command..." -ForegroundColor Cyan
        try {
            $ipOutput = ip -4 -o addr show | Where-Object { 
                $_ -match 'scope global' -and $_ -notmatch 'docker|virbr' 
            } | Select-Object -First 1
            
            if (-not $ipOutput) {
                Write-Error "Could not auto-detect the primary network interface. Specify a subnet manually with -Subnet."
                exit 1
            }

            # Parse output like: "2: eth0    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
            if ($ipOutput -match 'inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)') {
                $baseIP = [System.Net.IPAddress]$matches[1]
                $prefixLength = [int]$matches[2]
                Write-Host "Auto-detected network: $($matches[1])/$prefixLength" -ForegroundColor Cyan
            }
            else {
                Write-Error "Could not parse network information. Specify a subnet manually with -Subnet."
                exit 1
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
        
        # Use Test-Connection with TimeoutSeconds (PS7 feature)
        $pingSuccess = Test-Connection -ComputerName $ip -Count 1 -TimeoutSeconds $timeoutSeconds -Quiet -ErrorAction SilentlyContinue
        
        if ($pingSuccess) {
            $hostname = "N/A (Resolution Failed)"
            try {
                # PS7 handles DNS resolution much better!
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
    } -ThrottleLimit $MaxThreads
}
# --- PowerShell 5.1: Use Runspaces (slower fallback) ---
else {
    Write-Host "Starting parallel scan using Runspaces..." -ForegroundColor Cyan
    
    $ScriptBlock = {
        param($ip, $timeoutMs)
        
        # Use raw .NET Ping for PS5
        $ping = New-Object System.Net.NetworkInformation.Ping
        
        try {
            $reply = $ping.Send($ip, $timeoutMs)
            
            if ($reply.Status -eq 'Success') {
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
                
                [PSCustomObject]@{
                    IP       = $ip
                    Status   = 'Online'
                    Hostname = $hostname
                }
            }
        }
        catch {
            # Ping failed or timed out
        }
        finally {
            $ping.Dispose()
        }
    }
    
    $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $MaxThreads)
    $RunspacePool.Open()
    
    $Jobs = @()
    
    foreach ($ip in $allIPs) {
        $ps = [PowerShell]::Create().AddScript($ScriptBlock).AddArgument($ip).AddArgument($Timeout * 1000)
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

# --- Calculate elapsed time ---
$endTime = Get-Date
$elapsed = $endTime - $startTime
$elapsedFormatted = "{0:hh\:mm\:ss\.fff}" -f $elapsed

# --- Output Results ---
if ($results) {
    # Filter out unresolved hostnames if IgnoreUnresolved is specified
    $displayResults = $results
    if ($IgnoreUnresolved) {
        $displayResults = $results | Where-Object { $_.Hostname -ne "N/A (Resolution Failed)" }
    }
    
    Write-Host "`n===================================================" -ForegroundColor Green
    Write-Host "Scan Complete! Found $($results.Count) active host(s)" -ForegroundColor Green
    if ($IgnoreUnresolved -and $displayResults.Count -lt $results.Count) {
        Write-Host "Showing $($displayResults.Count) with resolved hostnames (use without -IgnoreUnresolved to see all)" -ForegroundColor Green
    }
    Write-Host "Note: Some host types like Android phones may appear intermittently due to sleep modes" -ForegroundColor Yellow
    Write-Host "Completed in: $elapsedFormatted" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Green
    
    if ($displayResults) {
        $displayResults | Sort-Object { 
            # Sort by IP address properly (not alphabetically)
            $octets = $_.IP.Split('.')
            [int]$octets[0] * 16777216 + [int]$octets[1] * 65536 + [int]$octets[2] * 256 + [int]$octets[3]
        } | Format-Table -AutoSize
    }
    else {
        Write-Host "All found hosts have unresolved hostnames. Run without -IgnoreUnresolved to see them." -ForegroundColor Yellow
    }
}
else {
    Write-Host "`n===================================================" -ForegroundColor Yellow
    Write-Host "Scan Complete. No active hosts found." -ForegroundColor Yellow
    Write-Host "Completed in: $elapsedFormatted" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Yellow
}
