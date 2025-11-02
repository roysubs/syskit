#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pings a range of IP addresses and resolves hostnames for active IPs.

.DESCRIPTION
    This script first uses 'ping-iprange-PS5.ps1' to identify active IP addresses
    within a specified start and end range. For each active IP address found,
    it then attempts to perform a reverse DNS lookup to determine its hostname.
    The results, showing IP addresses and their resolved hostnames, are displayed
    in a table.
    If run without parameters, this help message is displayed.

.PARAMETER StartAddress
    The starting IP address of the range to scan. This is mandatory for operation.

.PARAMETER EndAddress
    The ending IP address of the range to scan. This is mandatory for operation.

.PARAMETER PingScriptPath
    The path to the 'ping-iprange-PS5.ps1' script. Defaults to './ping-iprange-PS5.ps1'
    (assuming it's in the same directory as this script).

.PARAMETER Help
    Displays this help message.

.EXAMPLE
    ./resolve-iprange.ps1 -StartAddress 192.168.1.1 -EndAddress 192.168.1.10

    IP           Hostname
    --           --------
    192.168.1.1  router.local
    192.168.1.5  fileserver.local
    192.168.1.7  N/A (Resolution Failed)

    This example scans IPs from 192.168.1.1 to 192.168.1.10, pings them,
    and then tries to resolve hostnames for those that respond.

.EXAMPLE
    ./resolve-iprange.ps1 -Help

    Displays this help message.

.EXAMPLE
    ./resolve-iprange.ps1

    Displays this help message because no parameters were provided.

.NOTES
    Relies on the 'ping-iprange.ps1' script for the initial ping sweep.
    Ensure 'ping-iprange.ps1' is executable and its path is correct.
    DNS resolution can be slow if many hosts are found or DNS servers are unresponsive.
#>
[CmdletBinding(DefaultParameterSetName = 'ShowHelp')]
param (
    [Parameter(ParameterSetName = 'ResolveRange', Mandatory = $true, Position = 0, HelpMessage = "The starting IP address of the range.")]
    [System.Net.IPAddress]$StartAddress,

    [Parameter(ParameterSetName = 'ResolveRange', Mandatory = $true, Position = 1, HelpMessage = "The ending IP address of the range.")]
    [System.Net.IPAddress]$EndAddress,

    [Parameter(ParameterSetName = 'ResolveRange', Mandatory = $false, HelpMessage = "Path to the 'ping-iprange.ps1' script.")]
    [string]$PingScriptPath = "./ping-iprange-PS5.ps1", # Assuming ping-iprange.ps1 is the correct name

    [Parameter(ParameterSetName = 'ShowHelp', HelpMessage = "Display this help message.")]
    [Switch]$Help
)

# --- Initial Check for Help Request ---
# If the 'ShowHelp' parameter set is active (either by default with no params, or explicitly with -Help),
# display help and exit.
if ($PSCmdlet.ParameterSetName -eq 'ShowHelp') {
    # This will display the comment-based help at the top of the script.
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0 # Exit gracefully after showing help
}

# --- Validation and Setup (only if not showing help) ---

# Ensure the helper ping script exists and is executable
Write-Verbose "Checking for ping script at '$PingScriptPath'..."
if (-not (Test-Path $PingScriptPath -PathType Leaf)) {
    Write-Error "Error: The ping script '$PingScriptPath' was not found or is not a file."
    exit 1
}

Write-Verbose "Pinging IP range from $StartAddress to $EndAddress using '$PingScriptPath'..."

# Prepare parameters for calling ping-iprange.ps1
$PingParams = @{
    StartAddress = $StartAddress
    EndAddress   = $EndAddress
}
# Forward the -Verbose switch if it was used with resolve-iprange.ps1
if ($PSBoundParameters.ContainsKey('Verbose') -and $VerbosePreference -ne [System.Management.Automation.ActionPreference]::SilentlyContinue) {
    $PingParams.Verbose = $true
}

# --- Execute Ping Sweep ---
$PingOutput = @() # Initialize to an empty array
try {
    # Corrected Write-Verbose line
    Write-Verbose "Executing: $PingScriptPath @($(($PingParams | ForEach-Object { "-$($_.Key) $($_.Value)" } ) -join ' '))"
    $PingOutput = & $PingScriptPath @PingParams
}
catch {
    Write-Error "An error occurred while executing '$PingScriptPath': $($_.Exception.Message)"
    if ($_.ScriptStackTrace) {
        Write-Error "Script stack trace from called script: $($_.ScriptStackTrace)"
    }
    exit 1
}

# Extract System.Net.IPAddress objects from the output
# ping-iprange.ps1 returns objects like: @{ IPAddress = [System.Net.IPAddress]; Bytes = ... }
$ActiveIPObjects = $PingOutput | Where-Object { $_ -ne $null -and $_.IPAddress -ne $null } | Select-Object -ExpandProperty IPAddress

if ($ActiveIPObjects.Count -eq 0) {
    Write-Host "No active IP addresses found in the range $StartAddress - $EndAddress." -ForegroundColor Yellow
    exit 0
}

Write-Verbose "Active IP Addresses found by '$PingScriptPath':"
if ($PSBoundParameters.ContainsKey('Verbose') -and $VerbosePreference -ne [System.Management.Automation.ActionPreference]::SilentlyContinue) {
    $ActiveIPObjects | ForEach-Object { Write-Verbose $_.IPAddressToString }
}
Write-Output "Attempting to resolve hostnames for active IP addresses..."

# --- Resolve Hostnames for Active IPs ---
Write-Verbose "Attempting to resolve hostnames for active IP addresses..."
$Results = @()

foreach ($IPAddressObj in $ActiveIPObjects) {
    $IPString = $IPAddressObj.IPAddressToString
    $Hostname = "N/A" # Default hostname

    Write-Verbose "Resolving hostname for $IPString..."
    try {
        $HostEntry = [System.Net.Dns]::GetHostEntry($IPAddressObj)
        # Check if HostEntry is not null and HostName is not whitespace
        if ($HostEntry -and -not [string]::IsNullOrWhiteSpace($HostEntry.HostName)) {
            $Hostname = $HostEntry.HostName
        } else {
            $Hostname = "N/A (No Hostname)"
            Write-Verbose "DNS lookup for $IPString returned an entry but no valid hostname."
        }
    }
    catch [System.Net.Sockets.SocketException] {
        # Using -f format operator for robustness against parser errors
        Write-Verbose ("DNS resolution failed for {0} (SocketException): {1}" -f $IPString, $_.Exception.Message)
        $Hostname = "N/A (Resolution Failed)"
    }
    catch {
        $ErrorMessage = if ($_.Exception -and $_.Exception.Message) { $_.Exception.Message } else { "An unknown error occurred during DNS lookup." }
        Write-Warning ("An unexpected error occurred during DNS lookup for {0}: {1}" -f $IPString, $ErrorMessage)
        $Hostname = "N/A (Error)"
    }

    $Results += [PSCustomObject]@{
        IP       = $IPString
        Hostname = $Hostname
    }
}

# --- Output Results ---
if ($Results.Count -gt 0) {
    Write-Host "`nResolved Hostnames:" -ForegroundColor Green
    $Results | Format-Table -AutoSize
} else {
    # This should ideally not be reached if ActiveIPObjects.Count > 0,
    # unless all DNS lookups failed in a way that didn't populate $Results.
    Write-Host "No hostnames could be resolved or displayed (active IPs were found but processing failed)." -ForegroundColor Yellow
}

Write-Verbose "Script finished."
