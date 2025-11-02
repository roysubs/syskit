#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Sends ICMP echo request packets to a range of IPv4 addresses between two given addresses.

.DESCRIPTION
    This function lets you sends ICMP echo request packets ("pings") to 
    a range of IPv4 addresses using an asynchronous method.

    Therefore this technique is very fast but comes with a warning.
    Ping sweeping a large subnet or network with many switches may result in 
    a peak of broadcast traffic.
    Use the -Interval parameter to adjust the time between each ping request.
    For example, an interval of 60 milliseconds is suitable for wireless networks.
    The RawOutput parameter switches the output to an unformatted
    [System.Net.NetworkInformation.PingReply[]].

.INPUTS
    None
    You cannot pipe input to this function.

.OUTPUTS
    The function only returns output from successful pings.

    Type: System.Net.NetworkInformation.PingReply

    The RawOutput parameter switches the output to an unformatted
    [System.Net.NetworkInformation.PingReply[]].

.NOTES
    Author  : G.A.F.F. Jakobs
    Created : August 30, 2014
    Version : 6

    Revision History: Kory Gill, 2016/01/09
        formatting
        added better error handling
        close progress indicator when complete

.EXAMPLE
    Ping-IPRange -StartAddress 192.168.1.1 -EndAddress 192.168.1.254 -Interval 20

    IPAddress                                 Bytes                     Ttl           ResponseTime
    ---------                                 -----                     ---           ------------
    192.168.1.41                                 32                      64                    371
    192.168.1.57                                 32                     128                      0
    192.168.1.64                                 32                     128                      1
    192.168.1.63                                 32                      64                     88
    192.168.1.254                                32                      64                      0

    In this example all the ip addresses between 192.168.1.1 and 192.168.1.254 are pinged using 
    a 20 millisecond interval between each request.
    All the addresses that reply the ping request are listed.

.LINK
    http://gallery.technet.microsoft.com/Fast-asynchronous-ping-IP-d0a5cf0e

#>

[CmdletBinding(DefaultParameterSetName = 'ShowHelp')]
[CmdletBinding(ConfirmImpact='Low')]
Param(
    [parameter(ParameterSetName = 'PingRange', Mandatory = $true, Position = 0)]
    [System.Net.IPAddress]$StartAddress,

    [parameter(ParameterSetName = 'PingRange', Mandatory = $true, Position = 1)]
    [System.Net.IPAddress]$EndAddress,

    [parameter(ParameterSetName = 'PingRange')]
    [int]$Interval = 30,

    [parameter(ParameterSetName = 'PingRange')]
    [Switch]$RawOutput = $false,

    [parameter(ParameterSetName = 'ShowHelp', HelpMessage = 'Display help information')]
    [Switch]$Help
)

# Notes:
# Use "#!/usr/bin/env pwsh" instead of "#!/usr/bin/pwsh" as env will search path for pwsh, more portable
# -? is not so common in Linux, so add [Switch]$Help and define it

# Use [CmdletBinding()] when you want your script or function to behave like a native cmdlet.
# Includes advanced parameter handling (e.g., multiple parameter sets or validation).
# Includes support for -WhatIf / -Confirm, and common parameters like -Verbose and -ErrorAction.
# ConfirmImpact is an option for [CmdletBinding()] that -Confirm impact (e.g., Low, Medium, High).
# It determines when PowerShell will automatically prompt the user for confirmation if -Confirm
# isn't explicitly provided.
# Low: Rarely prompts for confirmation unless explicitly requested.
# Medium: Prompts for confirmation when $ConfirmPreference is Medium or lower (default in most cases).
# High: Always prompts for confirmation unless -Confirm:$false is specified.

# Show help if the Help switch is used or no parameters are provided
if ($PSCmdlet.ParameterSetName -eq 'ShowHelp' -or $Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    return
}

# Check for mandatory parameters
if (-not $StartAddress -or -not $EndAddress) {
    Write-Error "Both -StartAddress and -EndAddress are required."
    return
}

$timeout = 2000

function New-Range ($start, $end) {

    [byte[]]$BySt = $start.GetAddressBytes()
    [Array]::Reverse($BySt)
    [byte[]]$ByEn = $end.GetAddressBytes()
    [Array]::Reverse($ByEn)
    $i1 = [System.BitConverter]::ToUInt32($BySt,0)
    $i2 = [System.BitConverter]::ToUInt32($ByEn,0)
    for ($x = $i1;$x -le $i2;$x++)
    {
        $ip = ([System.Net.IPAddress]$x).GetAddressBytes()
        [Array]::Reverse($ip)
        [System.Net.IPAddress]::Parse($($ip -join '.'))
    }
}

$ipRange = New-Range $StartAddress $EndAddress
$IpTotal = $ipRange.Count
Get-Event -SourceIdentifier "ID-Ping*" | Remove-Event
Get-EventSubscriber -SourceIdentifier "ID-Ping*" | Unregister-Event

$ipRange | ForEach-Object {
    [string]$VarName = "Ping_" + $_.Address
    New-Variable -Name $VarName -Value (New-Object System.Net.NetworkInformation.Ping)
    Register-ObjectEvent -InputObject (Get-Variable $VarName -ValueOnly) -EventName PingCompleted -SourceIdentifier "ID-$VarName"
    (Get-Variable $VarName -ValueOnly).SendAsync($_,$timeout,$VarName)
    Remove-Variable $VarName

    try
    {
        $pending = (Get-Event -SourceIdentifier "ID-Ping*").Count
    } 
    catch [System.InvalidOperationException]
    {
        $pending = 0
    }

    $index = [array]::indexof($ipRange,$_)
    Write-Progress -Activity "Sending ping to" -Id 1 -status $_.IPAddressToString -PercentComplete (($index / $IpTotal)  * 100)

    $percentComplete = ($($index - $pending), 0 | Measure-Object -Maximum).Maximum

    Write-Progress -Activity "ICMP requests pending" -Id 2 -ParentId 1 -Status ($index - $pending) -PercentComplete ($percentComplete/$IpTotal * 100)

    Start-Sleep -Milliseconds $Interval
}

Write-Progress -Activity "Done sending ping requests" -Id 1 -Status 'Waiting' -PercentComplete 100 

while ($pending -lt $IpTotal) {

    Wait-Event -SourceIdentifier "ID-Ping*" | Out-Null

    Start-Sleep -Milliseconds 10

    try
    {
        $pending = (Get-Event -SourceIdentifier "ID-Ping*").Count
    }
    catch [System.InvalidOperationException]
    {
        $pending = 0
    }

    $percentComplete = ($($IpTotal - $pending), 0 | Measure-Object -Maximum).Maximum

    Write-Progress -Activity "ICMP requests pending" -Id 2 -ParentId 1 -Status ($IpTotal - $pending) -PercentComplete ($percentComplete/$IpTotal * 100)
}

Write-Progress -Completed -Id 2 -ParentId 1 -Activity "Completed"
Write-Progress -Completed -Id 1 -Activity "Completed"
$Reply = @()

if ($RawOutput)
{
    Get-Event -SourceIdentifier "ID-Ping*" | ForEach { 
        if ($_.SourceEventArgs.Reply.Status -eq "Success")
        {
            $Reply += $_.SourceEventArgs.Reply
        }
        Unregister-Event $_.SourceIdentifier
        Remove-Event $_.SourceIdentifier
    }
}
else
{
    Get-Event -SourceIdentifier "ID-Ping*" | ForEach-Object { 
        if ($_.SourceEventArgs.Reply.Status -eq "Success")
        {
            $pinger = @{
                IPAddress = $_.SourceEventArgs.Reply.Address
                Bytes = $_.SourceEventArgs.Reply.Buffer.Length
                Ttl = $_.SourceEventArgs.Reply.Options.Ttl
                ResponseTime = $_.SourceEventArgs.Reply.RoundtripTime
            }
            $Reply += New-Object PSObject -Property $pinger
        }
        Unregister-Event $_.SourceIdentifier
        Remove-Event $_.SourceIdentifier
    }
}

if ($Reply.Count -eq 0)
{
    Write-Verbose "Ping-IPRange : No IP address responded" -Verbose
}

return $Reply

# # Entry point for the script
# if ($PSCommandPath -eq $MyInvocation.InvocationName) {
#     param (
#         [Parameter(Mandatory = $true)]
#         [System.Net.IPAddress]$StartAddress,
#         [Parameter(Mandatory = $true)]
#         [System.Net.IPAddress]$EndAddress
#     )
#     Ping-IPRange -StartAddress $StartAddress -EndAddress $EndAddress
# }

### #!/bin/bash
### pwsh ./ping-iprange.ps1 "$@"
