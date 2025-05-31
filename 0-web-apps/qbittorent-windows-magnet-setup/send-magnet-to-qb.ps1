##################################
# send-magnet-to-qb.ps1 - Logging Version (Corrected Path Handling)
# Sends a magnet link to remote qBittorrent Web UI on port 8080 via its API.
# Logs output and errors to a .log file in the same directory.
##################################
# Note Check IP, username, and password if not working correctly
##################################

param (
    [string]$magnetLink
)

# --- Configuration ---
# qBittorrent Web UI url and port, username, and password
$qbWebUIHost = "http://192.168.1.140:8080"
$username = "admin"
$password = "adminadmin"

$scriptPath = $MyInvocation.MyCommand.Definition   # Full path
$scriptDir = Split-Path -Path $scriptPath -Parent  # Script Parent directory
$scriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)  # Base name (i.e., no extension)
$logFilePath = Join-Path -Path $scriptDir -ChildPath "$scriptBaseName.log"    # Log file full path

# --- Function for logging output ---
function Write-Log {
    param (
        [string]$message,
        [string]$logFile # Accept the log file path as a parameter
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp $message"
    # Append the log entry to the file
    # Use -Force to create the directory if it doesn't exist (though it should exist if the script is there)
    # Use -Append to add to the end of the file
    Add-Content -Path $logFile -Value $logEntry -Force
}

# --- Main Logic ---

# Pass the determined log file path to the logging function
# Write-Log "Script started." $logFilePath
$magnetTitle = $magnetLink.Split('&') | Where-Object { $_ -like "dn=*" } | ForEach-Object { $_ -replace "dn=", "" }
Write-Log "Send '$magnetTitle' to '$qbWebUIHost'" $logFilePath

# Validate input
if ([string]::IsNullOrWhiteSpace($magnetLink)) {
    Write-Log "ERROR: No magnet link provided. Exiting." $logFilePath
    exit 1   # Exit with a non-zero status to indicate failure
}

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

# --- Attempt Authentication ---
# Write-Log "Attempting authentication..." $logFilePath
try {
    # Use ErrorAction Stop to catch HTTP errors like 401, 404 as exceptions
    $loginResponse = Invoke-WebRequest -Uri "$qbWebUIHost/api/v2/auth/login" -Method Post -Body @{
        username = $username
        password = $password
    } -WebSession $session -ErrorAction Stop
    # Write-Log "Authentication Invoke-WebRequest completed." $logFilePath

    # Authentication success should return "Ok." in the content for API v2 login
    if ($loginResponse.Content -ne "Ok.") {
        # Authentication failed based on content response
        Write-Log "ERROR: Failed to authenticate on '$qbWebUIHost'; check IP:Port, username, and password" $logFilePath
        Write-Log "Response Content: $($loginResponse.Content). Exiting." $logFilePath
        exit 1
    }
    Write-Log "SUCCESS: Authentication returned 'Ok.'" $logFilePath

} catch {
    # Catch errors during Invoke-WebRequest (e.g., connection refused, host not found, firewall blocked)
    Write-Log "ERROR: Could not connect to qBittorrent Web UI or authentication failed at network level. Error details: $($_.Exception.Message). Exiting." $logFilePath
    exit 1
}

# --- Attempt to Add Magnet Link ---
# Write-Log "Attempting to add magnet link..." $logFilePath
try {
    # Use ErrorAction Stop to catch HTTP errors like 409 (Conflict)
    $addTorrentResponse = Invoke-WebRequest -Uri "$qbWebUIHost/api/v2/torrents/add" -Method Post -Body @{
        urls = $magnetLink # 'urls' is the correct parameter name for magnet links
    } -WebSession $session -ErrorAction Stop

    # Write-Log "Add torrent Invoke-WebRequest completed." $logFilePath

    # API returns 200 OK on success for adding torrents
    if ($addTorrentResponse.StatusCode -ne 200) {
        # API call was made, but returned a non-200 status code
        # This could indicate an issue with the magnet link format, duplicates, or an internal server error
        Write-Log "ERROR: Failed to add the magnet link. Status code: $($addTorrentResponse.StatusCode). Response Content Sample: $($addTorrentResponse.Content | Select-Object -First 200). Exiting." $logFilePath
        exit 1
    }

    # If we reach here, the magnet link was successfully added (StatusCode 200)
    Write-Log "SUCCESS: Magnet link added successfully (Status Code 200)." $logFilePath

} catch {
    # Catch errors during Invoke-WebRequest for adding torrent (e.g., network interruption after login)
    Write-Log "ERROR: An error occurred while trying to add the magnet link after successful authentication. Error details: $($_.Exception.Message). Exiting." $logFilePath
    exit 1
}

# Write-Log "Script finished." $logFilePath
exit 0    # Explicitly exit with status 0 on success
