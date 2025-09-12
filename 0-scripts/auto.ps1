cat << 'EOF' > network-scan.ps1
#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Scans the local network to find active hosts and resolve their hostnames.

.DESCRIPTION
    A self-contained script to automate network discovery. It determines the local network range automatically or accepts a manually specified subnet. It then pings all hosts in the range to find which are online and performs a reverse DNS lookup to get their hostnames.

.PARAMETER Subnet
    Optional. Manually specifies the target subnet in CIDR notation (e.g., "192.168.1.0/24"). This overrides auto-detection and is recommended when running from WSL.

.PARAMETER Timeout
    The timeout in seconds for each ping. Defaults to 1 second.
#>
[CmdletBinding(DefaultParameterSetName = 'ShowHelp')]
param (
    [Parameter(ParameterSetName = 'ResolveAuto', Mandatory = $false, Position = 0)]
    [string]$Subnet,

    [Parameter(ParameterSetName = 'ResolveAuto')]
    [int]$Timeout = 1,

    [Parameter(ParameterSetName = 'ShowHelp')]
    [Switch]$Help
)

if ($PSCmdlet.ParameterSetName -eq 'ShowHelp' -or $PSBoundParameters.ContainsKey('Help')) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

# --- Determine Network Range ---
$allIPs = @()
if ($Subnet) {
    Write-Verbose "Using manually specified subnet: $Subnet"
    try {
        $ip, $prefixStr = $Subnet.Split('/')
        if (-not $prefixStr) { throw "Invalid CIDR format." }
        $baseIP = [System.Net.IPAddress]$ip
        $prefixLength = [int]$prefixStr
    }
    catch {
        Write-Error ("Invalid subnet format '{0}'. Please use CIDR notation (e.g., 192.168.1.0/24)." -f $Subnet)
        exit 1
    }
}
else {
    Write-Verbose "Attempting to auto-detect primary local network..."
    $ipConfig = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
    if (-not $ipConfig) {
        Write-Error "Could not auto-detect the primary network. Specify a subnet manually with -Subnet."
        exit 1
    }
    $baseIP = $ipConfig.IPv4Address.IPAddress
    $prefixLength = $ipConfig.IPv4Address.PrefixLength
    Write-Verbose "Detected IP: $baseIP with prefix length: $prefixLength"
}

try {
    # Calculate network range
    $ipAddressBytes = $baseIP.GetAddressBytes()
    $mask = [uint32]::MaxValue -shl (32 - $prefixLength)
    $subnetMaskBytes = [System.BitConverter]::GetBytes($mask)
    if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($subnetMaskBytes) }

    $networkAddressBytes = for ($i = 0; $i -lt 4; $i++) { $ipAddressBytes[$i] -band $subnetMaskBytes[$i] }
    $networkAddress = [System.Net.IPAddress]::new($networkAddressBytes)
    
    # Use -bnot instead of ~ for maximum compatibility
    $invertedMaskBytes = $subnetMaskBytes | ForEach-Object { [byte](-bnot $_) }
    $broadcastAddressBytes = for ($i = 0; $i -lt 4; $i++) { $networkAddressBytes[$i] -bor $invertedMaskBytes[$i] }

    $start = [System.BitConverter]::ToUInt32($networkAddressBytes, 0)
    $end = [System.BitConverter]::ToUInt32($broadcastAddressBytes, 0)
    
    for ($i = ($start + 1); $i -lt $end; $i++) {
        $ipBytes = [System.BitConverter]::GetBytes($i)
        $allIPs += ([System.Net.IPAddress]$ipBytes).ToString()
    }

    Write-Host "Scanning $($allIPs.Count) hosts in subnet $($networkAddress.IPAddressToString)/$prefixLength..." -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to calculate network range. Error: $($_.Exception.Message)"
    exit 1
}

# --- Ping Sweep and DNS Resolution ---
$results = $allIPs | ForEach-Object -Parallel {
    $ip = $_
    Write-Verbose "Pinging $ip..."
    
    $pingSuccess = Test-Connection -ComputerName $ip -Count 1 -TimeoutSeconds $using:Timeout -Quiet -ErrorAction SilentlyContinue
    
    if ($pingSuccess) {
        $hostname = "N/A (Resolution Failed)"
        try {
            $dns = [System.Net.Dns]::GetHostEntry($ip)
            if ($dns -and -not [string]::IsNullOrWhiteSpace($dns.HostName)) {
                $hostname = $dns.HostName
            }
        } catch {}
        
        [PSCustomObject]@{
            IP       = $ip
            Status   = 'Online'
            Hostname = $hostname
        }
    }
} -ThrottleLimit 100

# --- Output Results ---
if ($results) {
    Write-Host "`nScan Complete. Found $($results.Count) active host(s):" -ForegroundColor Green
    $results | Sort-Object { [System.Version]$_.IP } | Format-Table -AutoSize
}
else {
    Write-Host "`nScan Complete. No active hosts found." -ForegroundColor Yellow
}
EOF
