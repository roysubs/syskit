####################
# setup-magnet-association-in-registry.ps1
####################

# Script path for the VBScript wrapper that will (silently) execute the PowerShell script.
# It is given `"%1`" (%1 is VBScript format for an argument, which is $1, the magnet link) as an argument.
$vbsScriptPath = "C:\Users\roysu\send-magnet-to-qb.vbs"

# Define the registry path for the magnet protocol
$regPath = "HKCU:\Software\Classes\magnet"

# Create the registry key for the magnet protocol
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force }

# Set the default value for the magnet protocol
Set-ItemProperty -Path $regPath -Name "(Default)" -Value "URL:Magnet Protocol"
Set-ItemProperty -Path $regPath -Name "URL Protocol" -Value ""

# Create the shell key for the open command
$regShellPath = "$regPath\shell\open\command"
if (-not (Test-Path $regShellPath)) { New-Item -Path $regShellPath -Force }
Set-ItemProperty -Path $regShellPath -Name "(Default)" -Value "`"wscript.exe`" `"$vbsScriptPath`" `"%1`""

Write-Host "Magnet protocol association has been created successfully."


# Old method, using the .ps1 directly always creates a console window every invocation, so .vbs wrapper is better.
# Define the script path where the send-magnet-to-qb.ps1 is stored
# $scriptPath = "C:\Users\roysu\send-magnet-to-qb.ps1"  # Update with the actual path to the PowerShell script
# Set the command to execute the PowerShell script with the magnet link as an argument
# Set-ItemProperty -Path $regShellPath -Name "(Default)" -Value "`"powershell.exe`" -ExecutionPolicy Bypass -File `"$scriptPath`" `"%1`""
# Set-ItemProperty -Path $regShellPath -Name "(Default)" -Value "`"wscript.exe`" `"`"$scriptPath`" `"%1`""
# $regPath = "HKCU:\Software\Classes\magnet\shell\open\command"
# Set-ItemProperty -Path $regPath -Name "(Default)" -Value "`"wscript.exe`" `"`"$scriptPath`" `"%1`""
