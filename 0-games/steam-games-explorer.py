#!/usr/bin/env python3
# Author: Roy Wiseman 2025-01
# Interactive Steam library explorer

import csv
import os
import glob
from collections import defaultdict
from datetime import datetime

def find_latest_csv():
    """Find the most recent steam-games CSV file."""
    home_dir = os.path.expanduser("~")
    pattern = os.path.join(home_dir, "steam-games_*.csv")
    csv_files = glob.glob(pattern)
    
    if not csv_files:
        return None
    
    # Sort by modification time, most recent first
    latest = max(csv_files, key=os.path.getmtime)
    return latest

def load_games(csv_file):
    """Load games from CSV file."""
    games = []
    try:
        with open(csv_file, 'r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            for row in reader:
                # Convert playtime to int
                try:
                    row['PlaytimeHrs'] = int(row.get('PlaytimeHrs', 0))
                except ValueError:
                    row['PlaytimeHrs'] = 0
                
                # Convert Metacritic to int
                try:
                    mc = row.get('Metacritic', 'N/A')
                    row['MetacriticScore'] = int(mc) if mc != 'N/A' else None
                except ValueError:
                    row['MetacriticScore'] = None
                
                games.append(row)
        return games
    except FileNotFoundError:
        print(f"❌ Error: File not found: {csv_file}")
        return None
    except Exception as e:
        print(f"❌ An error occurred: {e}")
        return None

def get_all_genres(games):
    """Extract all unique genres from the game library."""
    genres = set()
    for game in games:
        genre_str = game.get('Genres', '')
        if genre_str and genre_str != 'N/A':
            for genre in genre_str.split(', '):
                genres.add(genre.strip())
    return sorted(genres)

def show_hidden_gems(games, min_score=75, max_playtime=0):
    """Show unplayed games with high Metacritic scores."""
    gems = [g for g in games 
            if g['PlaytimeHrs'] <= max_playtime 
            and g['MetacriticScore'] is not None 
            and g['MetacriticScore'] >= min_score]
    
    gems.sort(key=lambda x: x['MetacriticScore'], reverse=True)
    
    print(f"\n{'='*80}")
    print(f"💎 HIDDEN GEMS (Metacritic {min_score}+, {max_playtime} hours or less)")
    print(f"{'='*80}\n")
    
    if not gems:
        print(f"No games found with Metacritic {min_score}+ and {max_playtime} hours or less playtime.")
        return
    
    print(f"Found {len(gems)} hidden gems:\n")
    for i, game in enumerate(gems[:20], 1):  # Show top 20
        genres = game.get('Genres', 'N/A')[:50]
        print(f"{i:2}. [{game['MetacriticScore']:2}] {game['Name']}")
        print(f"    Genre: {genres}")
        print(f"    Released: {game.get('ReleaseDate', 'N/A')}")
        print()

def show_top_played(games, limit=10):
    """Show most played games."""
    played = [g for g in games if g['PlaytimeHrs'] > 0]
    played.sort(key=lambda x: x['PlaytimeHrs'], reverse=True)
    
    print(f"\n{'='*80}")
    print(f"🏆 TOP {limit} MOST PLAYED GAMES")
    print(f"{'='*80}\n")
    
    if not played:
        print("No games with recorded playtime found.")
        return
    
    total_hours = sum(g['PlaytimeHrs'] for g in played)
    
    for i, game in enumerate(played[:limit], 1):
        genres = game.get('Genres', 'N/A')[:50]
        mc = f"[{game['MetacriticScore']}]" if game['MetacriticScore'] else "[--]"
        print(f"{i:2}. {mc} {game['Name']} - {game['PlaytimeHrs']} hours")
        print(f"    Genre: {genres}")
        print()
    
    print(f"Total playtime across all games: {total_hours:,} hours ({total_hours/24:.1f} days)")

def show_by_genre(games, genre):
    """Show games filtered by genre."""
    filtered = [g for g in games 
                if genre.lower() in g.get('Genres', '').lower()]
    
    print(f"\n{'='*80}")
    print(f"🎮 {genre.upper()} GAMES")
    print(f"{'='*80}\n")
    
    if not filtered:
        print(f"No {genre} games found.")
        return
    
    # Separate unplayed and played
    unplayed = [g for g in filtered if g['PlaytimeHrs'] == 0 and g['MetacriticScore'] is not None]
    played = [g for g in filtered if g['PlaytimeHrs'] > 0]
    
    unplayed.sort(key=lambda x: x['MetacriticScore'] if x['MetacriticScore'] else 0, reverse=True)
    played.sort(key=lambda x: x['PlaytimeHrs'], reverse=True)
    
    print(f"Total {genre} games: {len(filtered)}")
    print(f"  Unplayed: {len(unplayed)}")
    print(f"  Played: {len(played)}\n")
    
    if unplayed:
        print(f"Top Unplayed (by Metacritic score):")
        for i, game in enumerate(unplayed[:10], 1):
            mc = f"[{game['MetacriticScore']:2}]" if game['MetacriticScore'] else "[--]"
            print(f"  {i:2}. {mc} {game['Name']}")
        print()
    
    if played:
        print(f"Most Played:")
        for i, game in enumerate(played[:10], 1):
            mc = f"[{game['MetacriticScore']:2}]" if game['MetacriticScore'] else "[--]"
            print(f"  {i:2}. {mc} {game['Name']} - {game['PlaytimeHrs']} hrs")

def show_stats(games):
    """Show overall library statistics."""
    print(f"\n{'='*80}")
    print(f"📊 LIBRARY STATISTICS")
    print(f"{'='*80}\n")
    
    total = len(games)
    played = len([g for g in games if g['PlaytimeHrs'] > 0])
    unplayed = total - played
    total_hours = sum(g['PlaytimeHrs'] for g in games)
    
    with_metacritic = len([g for g in games if g['MetacriticScore'] is not None])
    avg_metacritic = sum(g['MetacriticScore'] for g in games if g['MetacriticScore'] is not None) / with_metacritic if with_metacritic > 0 else 0
    
    print(f"Total Games: {total:,}")
    print(f"  ✓ Played: {played:,} ({played/total*100:.1f}%)")
    print(f"  ✗ Unplayed: {unplayed:,} ({unplayed/total*100:.1f}%)")
    print()
    print(f"Total Playtime: {total_hours:,} hours ({total_hours/24:.1f} days)")
    if played > 0:
        print(f"Average per played game: {total_hours/played:.1f} hours")
    print()
    print(f"Games with Metacritic scores: {with_metacritic:,}")
    if with_metacritic > 0:
        print(f"Average Metacritic score: {avg_metacritic:.1f}")
    
    # Genre breakdown
    genre_counts = defaultdict(int)
    for game in games:
        genres_str = game.get('Genres', '')
        if genres_str and genres_str != 'N/A':
            for genre in genres_str.split(', '):
                genre_counts[genre.strip()] += 1
    
    print(f"\nTop 10 Genres:")
    sorted_genres = sorted(genre_counts.items(), key=lambda x: x[1], reverse=True)
    for i, (genre, count) in enumerate(sorted_genres[:10], 1):
        print(f"  {i:2}. {genre}: {count} games")

def show_quick_picks(games):
    """Show quick game recommendations for different moods."""
    print(f"\n{'='*80}")
    print(f"🎲 QUICK PICKS - WHAT TO PLAY TONIGHT")
    print(f"{'='*80}\n")
    
    # Short games (unplayed, high score)
    short = [g for g in games 
             if g['PlaytimeHrs'] == 0 
             and g['MetacriticScore'] is not None 
             and g['MetacriticScore'] >= 75
             and 'indie' in g.get('Genres', '').lower()]
    short.sort(key=lambda x: x['MetacriticScore'], reverse=True)
    
    print("🎯 Quick Indie Experience:")
    if short:
        game = short[0]
        print(f"  → {game['Name']} [Metacritic: {game['MetacriticScore']}]")
        print(f"     {game.get('Genres', 'N/A')}\n")
    else:
        print("  No unplayed indie games found.\n")
    
    # Action games
    action = [g for g in games 
              if g['PlaytimeHrs'] == 0 
              and g['MetacriticScore'] is not None 
              and g['MetacriticScore'] >= 75
              and 'action' in g.get('Genres', '').lower()]
    action.sort(key=lambda x: x['MetacriticScore'], reverse=True)
    
    print("⚔️  Action-Packed:")
    if action:
        game = action[0]
        print(f"  → {game['Name']} [Metacritic: {game['MetacriticScore']}]")
        print(f"     {game.get('Genres', 'N/A')}\n")
    else:
        print("  No unplayed action games found.\n")
    
    # Strategy games
    strategy = [g for g in games 
                if g['PlaytimeHrs'] == 0 
                and g['MetacriticScore'] is not None 
                and g['MetacriticScore'] >= 75
                and 'strategy' in g.get('Genres', '').lower()]
    strategy.sort(key=lambda x: x['MetacriticScore'], reverse=True)
    
    print("🧠 Strategic Thinking:")
    if strategy:
        game = strategy[0]
        print(f"  → {game['Name']} [Metacritic: {game['MetacriticScore']}]")
        print(f"     {game.get('Genres', 'N/A')}\n")
    else:
        print("  No unplayed strategy games found.\n")

def search_games(games, search_term):
    """Search for games by name."""
    results = [g for g in games 
               if search_term.lower() in g['Name'].lower()]
    
    print(f"\n{'='*80}")
    print(f"🔍 SEARCH RESULTS: '{search_term}'")
    print(f"{'='*80}\n")
    
    if not results:
        print(f"No games found matching '{search_term}'")
        return
    
    print(f"Found {len(results)} game(s):\n")
    for game in results:
        mc = f"[{game['MetacriticScore']}]" if game['MetacriticScore'] else "[--]"
        print(f"{mc} {game['Name']}")
        print(f"  Genre: {game.get('Genres', 'N/A')}")
        print(f"  Playtime: {game['PlaytimeHrs']} hours")
        print(f"  Released: {game.get('ReleaseDate', 'N/A')}")
        print(f"  Developer: {game.get('Developer', 'N/A')}")
        print()

def show_menu():
    """Display the main menu."""
    print(f"\n{'='*80}")
    print("🎮 STEAM GAMES EXPLORER")
    print(f"{'='*80}")
    print("\n1. 💎 Hidden Gems (unplayed, high scores)")
    print("2. 🏆 Top Most Played Games")
    print("3. 🎯 Browse by Genre")
    print("4. 📊 Library Statistics")
    print("5. 🎲 Quick Picks (What to play tonight)")
    print("6. 🔍 Search for a Game")
    print("7. 📁 Load Different CSV File")
    print("0. 🚪 Exit")
    print(f"{'='*80}")

def main():
    print("\n" + "="*80)
    print("STEAM GAMES EXPLORER")
    print("="*80)
    
    # Find latest CSV
    csv_file = find_latest_csv()
    
    if not csv_file:
        print("\n❌ No steam-games CSV files found in home directory.")
        print("   Run steam-games-collect.py first to generate your library data.")
        return
    
    # Show which file we're using
    filename = os.path.basename(csv_file)
    mod_time = datetime.fromtimestamp(os.path.getmtime(csv_file))
    print(f"\n✅ Found: {filename}")
    print(f"   Generated: {mod_time.strftime('%Y-%m-%d %H:%M:%S')}")
    
    # Load games
    games = load_games(csv_file)
    if not games:
        return
    
    print(f"   Loaded {len(games):,} games")
    
    while True:
        show_menu()
        choice = input("\nSelect an option: ").strip()
        
        if choice == '1':
            # Hidden Gems
            try:
                min_score = input("Minimum Metacritic score (default 75): ").strip()
                min_score = int(min_score) if min_score else 75
                max_hours = input("Maximum playtime hours (default 0): ").strip()
                max_hours = int(max_hours) if max_hours else 0
                show_hidden_gems(games, min_score, max_hours)
            except ValueError:
                print("❌ Invalid input. Using defaults.")
                show_hidden_gems(games)
        
        elif choice == '2':
            # Top Played
            try:
                limit = input("How many games to show (default 10): ").strip()
                limit = int(limit) if limit else 10
                show_top_played(games, limit)
            except ValueError:
                show_top_played(games)
        
        elif choice == '3':
            # Browse by Genre
            genres = get_all_genres(games)
            print(f"\n{'='*80}")
            print("AVAILABLE GENRES")
            print(f"{'='*80}\n")
            for i, genre in enumerate(genres, 1):
                print(f"{i:2}. {genre}")
            print()
            
            genre_input = input("Enter genre name (or number): ").strip()
            
            # Check if it's a number
            try:
                genre_num = int(genre_input)
                if 1 <= genre_num <= len(genres):
                    selected_genre = genres[genre_num - 1]
                    show_by_genre(games, selected_genre)
                else:
                    print("❌ Invalid genre number")
            except ValueError:
                # It's a text search
                show_by_genre(games, genre_input)
        
        elif choice == '4':
            # Statistics
            show_stats(games)
        
        elif choice == '5':
            # Quick Picks
            show_quick_picks(games)
        
        elif choice == '6':
            # Search
            search_term = input("Enter game name to search: ").strip()
            if search_term:
                search_games(games, search_term)
        
        elif choice == '7':
            # Load different file
            custom_file = input("Enter full path to CSV file: ").strip()
            if os.path.exists(custom_file):
                games = load_games(custom_file)
                if games:
                    csv_file = custom_file
                    print(f"✅ Loaded {len(games):,} games from {os.path.basename(custom_file)}")
            else:
                print("❌ File not found")
        
        elif choice == '0':
            print("\n👋 Thanks for exploring your Steam library!")
            print("="*80 + "\n")
            break
        
        else:
            print("❌ Invalid option. Please try again.")
        
        input("\nPress ENTER to continue...")

if __name__ == "__main__":
    main()
