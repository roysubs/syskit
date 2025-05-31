####################
# send-magnet-to-qb.ps1
####################
param ( [string]$magnetLink )

# qBittorrent Web UI information: updated these for your qBittorrent server
$qbWebUIHost = "http://192.168.1.140:8080"  # IP of qBittorrent server
$username = "admin"       # qBittorrent Web UI username
$password = "adminadmin"  # qBittorrent Web UI password (adminadmin is the default)

# Authenticate with qBittorrent Web UI
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$response = Invoke-WebRequest -Uri "$qbWebUIHost/api/v2/auth/login" -Method Post -Body @{
    username = $username
    password = $password
} -SessionVariable session -ErrorAction Stop

# Ensure authentication was successful
if ($response.Content -ne "Ok.") {
    Write-Host "Failed to authenticate with qBittorrent!"
    exit 1
}

# Add the magnet link to qBittorrent (correct key is 'urls', not 'magnetLink')
$response = Invoke-WebRequest -Uri "$qbWebUIHost/api/v2/torrents/add" -Method Post -Body @{
    urls = $magnetLink
} -WebSession $session -ErrorAction Stop

# Check if the request was successful
if ($response.StatusCode -eq 200) {
    Write-Host "Magnet link added successfully!"
} else {
    Write-Host "Failed to add magnet link. Status code: $($response.StatusCode)"
}
