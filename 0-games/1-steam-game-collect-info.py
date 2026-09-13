#!/usr/bin/env python3
# Author: Roy Wiseman 2025-04

# The Steam Store API (https://store.steampowered.com/api/appdetails) is not officially documented, and it has strict
# but undocumented rate limits — people generally estimate it to be around 20 requests per minute per IP (sometimes
# even less). To avoid HTTP status code 429 rate-limiting errors ("Too Many Requests"), we will stagger the collection
# with short # sleep pauses.

import requests
import time
import os
import configparser
import csv
import sys

home_dir = os.path.expanduser("~")
base_name = os.path.splitext(os.path.basename(__file__))[0]

INI_FILENAME = os.path.join(home_dir, base_name + ".ini")
CSV_FILENAME = os.path.join(home_dir, base_name + "-out.csv")
MD_FILENAME = os.path.join(home_dir, base_name + "-out.md")


def mask_key(key):
    if len(key) <= 8:
        return "*" * len(key)
    return key[:4] + "*" * (len(key) - 8) + key[-4:]


def load_or_create_ini():
    config = configparser.ConfigParser()
    if os.path.exists(INI_FILENAME):
        config.read(INI_FILENAME)
        if 'STEAM' in config and 'API_KEY' in config['STEAM'] and 'STEAM_ID' in config['STEAM']:
            saved_key = config['STEAM']['API_KEY']
            saved_id = config['STEAM']['STEAM_ID']

            print("=" * 70)
            print(f"Found saved settings in: {INI_FILENAME}")
            print("-" * 70)
            print(f"  API Key:   {mask_key(saved_key)}")
            print(f"  SteamID64: {saved_id}")
            print("=" * 70)
            choice = input("Use these? [Y/n, or 'd' to delete the file and start over]: ").strip().lower()

            if choice in ('', 'y', 'yes'):
                return saved_key, saved_id

            if choice in ('d', 'delete'):
                os.remove(INI_FILENAME)
                print(f"Deleted {INI_FILENAME}. Let's set it up again.\n")
            else:
                print("Okay, let's re-enter both values (they'll overwrite what's saved).\n")
    else:
        config['STEAM'] = {}

    if 'STEAM' not in config:
        config['STEAM'] = {}

    print("=" * 70)
    print("Steam Web API Key")
    print("-" * 70)
    print("Get one (free) here, while logged into Steam in your browser:")
    print("  https://steamcommunity.com/dev/apikey")
    print("Any text can go in the 'Domain Name' field, e.g. 'localhost'.")
    print("This key is tied to your account — treat it like a password.")
    print("=" * 70)
    api_key = input("Enter your Steam Web API Key: ").strip()

    print()
    print("=" * 70)
    print("SteamID64")
    print("-" * 70)
    print("Your 17-digit numeric Steam ID. Find it here:")
    print("  https://steamid.io/  (paste your profile URL or /id/ vanity name)")
    print("Or, if your profile is public, open your Steam profile page and")
    print("look at the URL — if it already shows /profiles/765611..., that")
    print("long number IS your SteamID64.")
    print("Note: your Steam profile AND game details must be set to Public")
    print("(Steam > Settings > Privacy Settings) for this script to work.")
    print("=" * 70)
    steam_id = input("Enter your SteamID64: ").strip()

    config['STEAM']['API_KEY'] = api_key
    config['STEAM']['STEAM_ID'] = steam_id

    with open(INI_FILENAME, 'w') as configfile:
        config.write(configfile)

    print(f"\nSaved to {INI_FILENAME} — you won't be asked again next run.\n")

    return api_key, steam_id


def get_owned_games(api_key, steam_id):
    url = 'https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/'
    params = {
        'key': api_key,
        'steamid': steam_id,
        'include_appinfo': True,
        'include_played_free_games': True
    }
    response = requests.get(url, params=params)
    if response.status_code != 200:
        print(f"Failed to retrieve owned games. Status code: {response.status_code}")
        if response.status_code == 403:
            print("403 usually means: wrong API key, wrong SteamID64, or your")
            print("profile/game-details privacy is not set to Public.")
        elif response.status_code == 400:
            print("400 usually means the SteamID64 is malformed (it should be")
            print("a 17-digit number, e.g. 76561198012345678) or missing.")
            print(f"Fix it by rerunning this script and choosing 'd' at the")
            print(f"saved-settings prompt to delete {os.path.basename(INI_FILENAME)}.")
        return []
    return response.json().get('response', {}).get('games', [])


def get_game_details(app_id, max_retries=5):
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
            print(f"Rate limited on AppID {app_id}. Waiting {wait}s and retrying...")
            time.sleep(wait)
            retries += 1
        else:
            print(f"Failed to retrieve details for AppID {app_id}. Status code: {response.status_code}")
            return {}
    print(f"Exceeded retries for AppID {app_id}. Skipping.")
    return {}


def write_csv_entry(game_data, csv_writer):
    csv_writer.writerow([
        game_data['name'],
        game_data['developer'],
        game_data['publisher'],
        game_data['release_date'],
        game_data['genres'],
        game_data['metacritic'],
        game_data['playtime'],
        game_data['last_played']
    ])


def write_markdown_entry(game_data, markdown_lines):
    markdown_lines.append(f"| {game_data['name']} | {game_data['developer']} | {game_data['publisher']} | {game_data['release_date']} | {game_data['genres']} | {game_data['metacritic']} | {game_data['playtime']} hrs | {game_data['last_played']} |")


def format_duration(seconds):
    seconds = int(seconds)
    hrs, rem = divmod(seconds, 3600)
    mins, secs = divmod(rem, 60)
    if hrs:
        return f"{hrs}h {mins}m {secs}s"
    if mins:
        return f"{mins}m {secs}s"
    return f"{secs}s"


def main():
    start_time = time.monotonic()
    start_clock = time.strftime('%Y-%m-%d %H:%M:%S')

    api_key, steam_id = load_or_create_ini()
    games = get_owned_games(api_key, steam_id)

    if not games:
        print("No games found or failed to retrieve games.")
        return

    # Open CSV and Markdown for writing
    with open(CSV_FILENAME, 'w', newline='', encoding='utf-8') as csvfile:
        csv_writer = csv.writer(csvfile, quoting=csv.QUOTE_ALL)
        csv_writer.writerow(["Name", "Developer", "Publisher", "ReleaseDate", "Genres", "Metacritic", "PlaytimeHrs", "LastPlayed"])

        markdown_lines = [
            "| Name | Developer | Publisher | Release Date | Genres | Metacritic | Playtime | Last Played |",
            "|------|-----------|-----------|---------------|--------|------------|----------|-------------|"
        ]

        for game in games:
            app_id = game.get('appid')
            name = game.get('name')
            playtime_forever = game.get('playtime_forever', 0) // 60
            last_played = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(game.get('rtime_last_played', 0)))

            details = get_game_details(app_id)
            time.sleep(1)

            if not details:
                continue

            developer = ', '.join(details.get('developers', []))
            publisher = ', '.join(details.get('publishers', []))
            release_date = details.get('release_date', {}).get('date', 'N/A')
            genres = ', '.join([genre['description'] for genre in details.get('genres', [])])
            metacritic = details.get('metacritic', {}).get('score', 'N/A')

            game_data = {
                'name': name,
                'developer': developer,
                'publisher': publisher,
                'release_date': release_date,
                'genres': genres,
                'metacritic': metacritic,
                'playtime': playtime_forever,
                'last_played': last_played
            }

            # Output to screen
            print("-" * 40)
            for k, v in game_data.items():
                print(f"{k.replace('_', ' ').title()}: {v}")

            # Write to CSV and Markdown
            write_csv_entry(game_data, csv_writer)
            write_markdown_entry(game_data, markdown_lines)

        # Final markdown write
        with open(MD_FILENAME, 'w', encoding='utf-8') as mdfile:
            mdfile.write('\n'.join(markdown_lines))

        print(f"\n✅ CSV saved to: {CSV_FILENAME}")
        print(f"✅ Markdown saved to: {MD_FILENAME}")

        elapsed = time.monotonic() - start_time
        end_clock = time.strftime('%Y-%m-%d %H:%M:%S')
        print(f"⏱  Started:  {start_clock}")
        print(f"⏱  Finished: {end_clock}")
        print(f"⏱  Total runtime: {format_duration(elapsed)} for {len(games)} games")

        with open(MD_FILENAME, 'a', encoding='utf-8') as mdfile:
            mdfile.write(f"\n\n_Generated {end_clock} — took {format_duration(elapsed)} for {len(games)} games._\n")


if __name__ == "__main__":
    main()
