#!/usr/bin/env pwsh

# Get list of disks from lsblk
$disks = lsblk -ndo NAME,MODEL,VENDOR,SIZE,SERIAL | ForEach-Object {
    if ($_ -match '^(\S+)\s+(.+)\s+(\S+)\s+(\S+)\s+(\S+)$') {
        [PSCustomObject]@{
            Device  = "/dev/$($matches[1])"
            Model   = $matches[2].Trim()
            Vendor  = $matches[3]
            Size    = $matches[4]
            Serial  = $matches[5]
        }
    }
}

function Get-SmartData {
    param (
        [string]$Device
    )
    
    # Run smartctl and fetch SMART data for the disk
    try {
        $smartData = sudo smartctl -A $Device 2>&1
        if ($smartData -match "smartctl: Permission denied") {
            return "Permission denied for accessing SMART data. Run with sudo."
        }
    } catch {
        return "Error running smartctl: $_"
    }

    # Now, look for the error/health-related SMART attributes
    $smartData = $smartData | Select-String -Pattern 'Reallocated_Sector_Ct|Current_Pending_Sector|Temperature|Error|Failure|SMART overall-health'

    if ($smartData.Count -eq 0) {
        return "No SMART data found or disk not supported"
    }

    return $smartData -join "`n"
}

# Iterate through each disk and get SMART data
foreach ($disk in $disks) {
    $smartData = Get-SmartData -Device $disk.Device
    Write-Host "`nSMART data for $($disk.Device):`n"
    Write-Host $smartData
    Write-Host
}

# Print lsblk information (first table)
$disks | Format-Table -AutoSize
