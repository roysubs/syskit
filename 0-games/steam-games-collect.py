#!/usr/bin/env python3
# Author: Roy Wiseman 2025-01
# Unified Steam game collection script - self-managing dependencies

import sys
import subprocess
import os
import warnings

# Suppress SSL warnings from urllib3 on macOS
warnings.filterwarnings('ignore', message='.*urllib3 v2.*')

def check_and_install_dependencies():
    """Check for required packages and install if missing."""
    required_packages = ['requests']
    missing_packages = []
    
    for package in required_packages:
        try:
            __import__(package)
        except ImportError:
            missing_packages.append(package)
    
    if missing_packages:
        print("\n" + "="*70)
        print("DEPENDENCY CHECK")
        print("="*70)
        print(f"\n📦 Missing required package(s): {', '.join(missing_packages)}")
        print("   Installing automatically...\n")
        
        for package in missing_packages:
            try:
                subprocess.check_call([
                    sys.executable, '-m', 'pip', 'install', 
                    '--user', '--quiet', package
                ])
                print(f"   ✅ Installed {package}")
            except subprocess.CalledProcessError:
                print(f"   ❌ Failed to install {package}")
                print(f"\nPlease install manually with:")
                print(f"   pip3 install --user {package}")
                sys.exit(1)
        
        print("\n✅ All dependencies installed successfully!")
        print("   Restarting script to load new modules...\n")
        print("="*70)
        
        # Restart the script with the same arguments
        os.execv(sys.executable, [sys.executable] + sys.argv)

# Check dependencies before importing them
check_and_install_dependencies()

# Now safe to import
import requests
import time
import json
import csv
from datetime import datetime

# Configuration file path
STEAM_ID_FILE = os.path.expanduser("~/.steam-id")

def print_instructions():
    """Display instructions for obtaining Steam credentials."""
    print("\n" + "="*70)
    print("STEAM API CREDENTIALS SETUP")
    print("="*70)
    print("\nYou need two pieces of information:")
    print("\n1. STEAM WEB API KEY")
    print("   " + "-"*66)
    print("   ⚠️  NOTE: You must have a non-limited Steam account")
    print("             (spent at least $5 USD on Steam)")
    print()
    print("   Steps:")
    print("   a) Go to: https://steamcommunity.com/dev/apikey")
    print("   b) Log in with your Steam credentials")
    print("   c) Enter 'localhost' in the Domain Name field")
    print("   d) Agree to Terms of Service and click 'Register'")
    print("   e) Copy your 32-character API key")
    print()
    print("2. STEAMID64")
    print("   " + "-"*66)
    print("   Option A - From your profile URL:")
    print("   a) Go to your Steam Profile (click your name in Steam)")
    print("   b) Look at the browser URL bar")
    print("   c) If it shows: steamcommunity.com/profiles/76561198XXXXXXXXX/")
    print("      That 17-digit number is your SteamID64")
    print()
    print("   Option B - If you have a custom URL:")
    print("   a) Go to: https://steamid.io")
    print("   b) Paste your profile link")
    print("   c) Copy the 'SteamID64' value shown")
    print()
    print("="*70)
    print("\n⚠️  SECURITY WARNING: Never share your API Key with anyone!")
    print("="*70)
    print()

def load_credentials():
    """Load Steam credentials from ~/.steam-id file."""
    if os.path.exists(STEAM_ID_FILE):
        try:
            with open(STEAM_ID_FILE, 'r') as f:
                data = json.load(f)
                api_key = data.get('api_key', '').strip()
                steam_id = data.get('steam_id', '').strip()
                if api_key and steam_id:
                    return api_key, steam_id
        except (json.JSONDecodeError, KeyError):
            pass
    return None, None

def save_credentials(api_key, steam_id):
    """Save Steam credentials to ~/.steam-id file."""
    data = {
        'api_key': api_key,
        'steam_id': steam_id,
        'created': datetime.now().isoformat()
    }
    with open(STEAM_ID_FILE, 'w') as f:
        json.dump(data, f, indent=2)
    # Set file permissions to user-read/write only for security
    os.chmod(STEAM_ID_FILE, 0o600)
    print(f"\n✅ Credentials saved to: {STEAM_ID_FILE}")

def setup_credentials():
    """Interactive setup for Steam credentials."""
    print_instructions()
    
    print("\nPlease enter your Steam credentials:")
    print("-" * 70)
    
    while True:
        api_key = input("\nSteam Web API Key (32 characters): ").strip()
        if len(api_key) == 32:
            break
        print("❌ Invalid API key length. Should be 32 characters.")
    
    while True:
        steam_id = input("SteamID64 (17 digits): ").strip()
        if len(steam_id) == 17 and steam_id.isdigit():
            break
        print("❌ Invalid SteamID64. Should be 17 digits.")
    
    save_credentials(api_key, steam_id)
    return api_key, steam_id

def get_owned_games(api_key, steam_id):
    """Fetch all owned games from Steam API."""
    url = 'https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/'
    params = {
        'key': api_key,
        'steamid': steam_id,
        'include_appinfo': True,
        'include_played_free_games': True
    }
    
    print("\n🔄 Fetching your Steam library...")
    response = requests.get(url, params=params)
    
    if response.status_code != 200:
        print(f"❌ Failed to retrieve games. Status code: {response.status_code}")
        if response.status_code == 403:
            print("   This usually means your API key or SteamID64 is incorrect.")
            print("   Or your Steam profile is set to private.")
        return []
    
    games = response.json().get('response', {}).get('games', [])
    print(f"✅ Found {len(games)} games in your library")
    return games

def get_game_details(app_id, max_retries=5):
    """Fetch detailed information for a specific game."""
    url = 'https://store.steampowered.com/api/appdetails'
    params = {'appids': app_id}
    
    retries = 0
    while retries < max_retries:
        response = requests.get(url, params=params)
        if response.status_code == 200:
            data = response.json()
            if str(app_id) in data and data[str(app_id)]['success']:
                return data[str(app_id)]['data']
            else:
                return {}
        elif response.status_code == 429:
            wait = 5 + retries * 5
            print(f"   ⏳ Rate limited on AppID {app_id}. Waiting {wait}s...")
            time.sleep(wait)
            retries += 1
        else:
            print(f"   ❌ Failed AppID {app_id}. Status: {response.status_code}")
            return {}
    
    print(f"   ⚠️  Exceeded retries for AppID {app_id}. Skipping.")
    return {}

def collect_game_data(api_key, steam_id):
    """Main collection function."""
    games = get_owned_games(api_key, steam_id)
    
    if not games:
        print("❌ No games found or failed to retrieve games.")
        return None
    
    # Calculate estimated time
    estimated_minutes = len(games) // 60 + 1
    
    print("\n" + "="*70)
    print("⏰ TIME ESTIMATE")
    print("="*70)
    print(f"\n📊 Games to process: {len(games)}")
    print(f"⏱️  Estimated time: ~{estimated_minutes} minutes")
    print(f"   (Steam API allows ~60 requests/minute)")
    print("\n💡 TIP: You can safely let this run in the background.")
    print("="*70)
    
    input("\nPress ENTER to begin collection...")
    
    # Start timer
    start_time = time.time()
    
    # Generate timestamped filename
    timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M')
    csv_filename = os.path.expanduser(f"~/steam-games_{timestamp}.csv")
    
    print(f"\n🔄 Collecting detailed information for {len(games)} games...\n")
    
    collected_data = []
    
    with open(csv_filename, 'w', newline='', encoding='utf-8') as csvfile:
        csv_writer = csv.writer(csvfile, quoting=csv.QUOTE_ALL)
        csv_writer.writerow([
            "Name", "Developer", "Publisher", "ReleaseDate", 
            "Genres", "Metacritic", "PlaytimeHrs", "LastPlayed"
        ])
        
        for idx, game in enumerate(games, 1):
            app_id = game.get('appid')
            name = game.get('name', 'Unknown')
            playtime_hrs = game.get('playtime_forever', 0) // 60
            rtime_last = game.get('rtime_last_played', 0)
            
            if rtime_last > 0:
                last_played = time.strftime('%Y-%m-%d %H:%M:%S', 
                                           time.localtime(rtime_last))
            else:
                last_played = 'Never'
            
            print(f"[{idx}/{len(games)}] {name}...", end=' ')
            
            details = get_game_details(app_id)
            time.sleep(1)  # Rate limiting: ~60 games/minute
            
            if details:
                developer = ', '.join(details.get('developers', ['N/A']))
                publisher = ', '.join(details.get('publishers', ['N/A']))
                release_date = details.get('release_date', {}).get('date', 'N/A')
                genres = ', '.join([g['description'] for g in details.get('genres', [])])
                metacritic = details.get('metacritic', {}).get('score', 'N/A')
                
                csv_writer.writerow([
                    name, developer, publisher, release_date,
                    genres, metacritic, playtime_hrs, last_played
                ])
                
                print(f"✓ ({playtime_hrs} hrs)")
            else:
                # Write basic info even if details failed
                csv_writer.writerow([
                    name, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 
                    playtime_hrs, last_played
                ])
                print("⚠️  (details unavailable)")
    
    # Calculate elapsed time
    elapsed_seconds = int(time.time() - start_time)
    elapsed_minutes = elapsed_seconds // 60
    remaining_seconds = elapsed_seconds % 60
    
    print(f"\n⏱️  Collection took: {elapsed_minutes} minutes and {remaining_seconds} seconds")
    
    return csv_filename

def main():
    print("\n" + "="*70)
    print("STEAM GAMES COLLECTION SCRIPT")
    print("="*70)
    
    # Load or setup credentials
    api_key, steam_id = load_credentials()
    
    if api_key and steam_id:
        print(f"\n✅ Found existing credentials in {STEAM_ID_FILE}")
        response = input("Use existing credentials? (Y/n): ").strip().lower()
        if response in ['n', 'no']:
            api_key, steam_id = setup_credentials()
    else:
        print(f"\n📝 No credentials found in {STEAM_ID_FILE}")
        api_key, steam_id = setup_credentials()
    
    # Collect game data
    csv_filename = collect_game_data(api_key, steam_id)
    
    if csv_filename:
        print("\n" + "="*70)
        print("✅ COLLECTION COMPLETE!")
        print("="*70)
        print(f"\n📊 Data saved to: {csv_filename}")
        print("\nYou can now analyze this data with your analysis scripts.")
        print("="*70 + "\n")
    else:
        print("\n❌ Collection failed. Please check your credentials and try again.\n")

if __name__ == "__main__":
    main()
