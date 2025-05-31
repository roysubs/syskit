#!/usr/bin/env python3
# Author: Roy Wiseman 2025-03

import csv

def analyze_steam_games(csv_file):
    """Analyzes a Steam game CSV file and provides recommendations."""

    games = []
    try:
        with open(csv_file, 'r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            for row in reader:
                games.append(row)
    except FileNotFoundError:
        return "Error: File not found."
    except Exception as e:
        return f"An error occurred: {e}"

    game_count = len(games)
    print(f"Total games in the CSV: {game_count}")

    skyrim_like_games = []
    soma_like_games = []

    for game in games:
        genres = game.get('Genres', '').lower()
        metacritic = game.get('Metacritic', 'N/A')
        try:
            metacritic_score = int(metacritic) if metacritic != 'N/A' else 0
        except ValueError:
            metacritic_score = 0
            
        name = game.get('Name')
        
        if "rpg" in genres and "action" in genres and metacritic_score >= 80:
            skyrim_like_games.append(game['Name'])
        if "adventure" in genres and "indie" in genres and (metacritic_score >= 75 or "horror" in genres):
            soma_like_games.append(game['Name'])

    print("\nRecommendations based on Skyrim:")
    if skyrim_like_games:
        for game_name in skyrim_like_games:
            print(f"- {game_name}")
    else:
        print("No Skyrim-like games found with high Metacritic scores.")

    print("\nRecommendations based on SOMA:")
    if soma_like_games:
        for game_name in soma_like_games:
            print(f"- {game_name}")
    else:
        print("No SOMA-like games found.")

analyze_steam_games("steam_game_info.csv")
