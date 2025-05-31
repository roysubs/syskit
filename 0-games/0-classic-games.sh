#!/bin/bash
# Author: Roy Wiseman 2025-01

# Game entries: name|Category|Description|apt package
games=(
    "rogue|Roguelike|Classic dungeon crawling game.|bsdgames-nonfree"
    "angband|Roguelike|Single-player, text-based, dungeon simulation game.|angband"
    "crawl|Roguelike|Dungeon Crawl, a text-based roguelike game.|crawl"
    "moria|Roguelike|Rogue-like game with an infinite dungeon, also known as Umoria.|moria"
    "nethack|Roguelike|Dungeon crawl game – text-based interface.|nethack-console"
    "2048|Puzzle|Slide and add puzzle game for text mode.|2048"
    "asciijump|Arcade|ASCII-art game about ski jumping.|asciijump"
    "bastet|Arcade|Ncurses Tetris clone with a bastard algorithm.|bastet"
    "bombardier|Puzzle|The GNU Bombing utility.|bombardier"
    "cavezofphear|Arcade|ASCII Boulder Dash clone.|cavezofphear"
    "freesweep|Puzzle|Text-based minesweeper.|freesweep"
    "greed|Puzzle|Clone of the DOS freeware game Greed.|greed"
    "ninvaders|Arcade|Space invaders-like game using ncurses.|ninvaders"
    "nsnake|Arcade|Classic snake game on the terminal.|nsnake"
    "pacman4console|Arcade|Ncurses-based Pac-Man game.|pacman4console"
    "petris|Arcade|Peter's Tetris – a Tetris(TM) clone.|petris"
    "vitetris|Arcade|Virtual terminal Tetris clone.|vitetris"
    "robotfindskitten|Zen|Zen simulation of robot finding kitten.|robotfindskitten"
    "sudoku|Puzzle|Console-based Sudoku.|sudoku"
    "tty-solitaire|Card|Ncurses-based Klondike solitaire game.|tty-solitaire"
    "adventure|Adventure|Colossal Cave Adventure game.|bsdgames"
    "animals|Trivia|AI animal guessing engine using binary tree DB.|bsdgames"
    "arithmetic|Educational|Drill on simple arithmetic problems.|bsdgames"
    "atc|Simulation|Air Traffic Controller simulation.|bsdgames"
    "backgammon|Board|The classic board game.|bsdgames"
    "battlestar|Adventure|Space adventure game.|bsdgames"
    "boggle|Word|Word search game.|bsdgames"
    "canfield|Card|Solitaire card game.|bsdgames"
    "cribbage|Card|The classic card game.|bsdgames"
    "gomoku|Board|Five in a row game.|bsdgames"
    "hangman|Word|Guess the word game.|bsdgames"
    "mille|Card|Mille Bornes card game.|bsdgames"
    "monop|Board|Monopoly game.|bsdgames"
    "phantasia|RPG|Fantasy role-playing game.|bsdgames"
    "quiz|Trivia|Random knowledge quiz.|bsdgames"
    "robots|Puzzle|Avoid the robots game.|bsdgames"
    "sail|Strategy|Naval strategy game.|bsdgames"
    "empire|Strategy|Sci-Fi strategy game.|empire"
    "snake|Arcade|Classic snake game.|bsdgames"
    "tetris|Arcade|Classic Tetris game.|bsdgames"
    "trek|Strategy|Star Trek game.|bsdgames"
)

usage() {
    echo "Usage: $0 [option]"
    echo "  -l              List games grouped by category"
    echo "  -h              Show this help message"
    echo "  -i <game>       Install a specific game (by name)"
    echo "  -iall           Install all games (unique apt packages)"
    echo "  -itype <type>   Install all games of a category (e.g., \"word\", \"WORD games\")"
    echo "  -r <game>       Run a game"
}

# Install a specific apt package
install_game() {
    echo "Installing packages: $*"
    sudo apt-get install -y "$@"
}

# Install all unique packages for all games
install_all_games() {
    local -A seen
    for entry in "${games[@]}"; do
        IFS='|' read -r _ _ _ apt <<< "$entry"
        seen["$apt"]=1
    done

    echo "Installing all unique packages:"
    # for pkg in "${!seen[@]}"; do
    #     install_game "$pkg"
    # done
    install_game "${!seen[@]}"
}

# Install games by category type (case-insensitive).
# After installing, list the games (name and description) that were installed.
install_by_type() {
    local search_type="$1"
    if [[ -z "$search_type" ]]; then
        echo "Please specify a type (e.g., Puzzle, Arcade, Roguelike, etc.)"
        exit 1
    fi

    # Normalize: lower-case and remove trailing " games" if present.
    search_type=$(echo "$search_type" | tr '[:upper:]' '[:lower:]')
    search_type=${search_type%" games"}

    local -A seen
    local installed_entries=()

    for entry in "${games[@]}"; do
        IFS='|' read -r name category description apt <<< "$entry"
        # Normalize the category to lower-case
        local norm_cat
        norm_cat=$(echo "$category" | tr '[:upper:]' '[:lower:]')
        if [[ "$norm_cat" == "$search_type" ]]; then
            seen["$apt"]=1
            installed_entries+=("$name – $description")
        fi
    done

    if [[ ${#seen[@]} -eq 0 ]]; then
        echo "No games found for type: $search_type"
        exit 1
    fi

    echo "Installing all '$search_type' games:"
    for pkg in "${!seen[@]}"; do
        install_game "$pkg"
    done

    echo -e "\nThe following games were installed in the '$search_type' category:"
    for entry in "${installed_entries[@]}"; do
        echo "$entry"
    done
}

# Run a game by name.
run_game() {
    if command -v "$1" &>/dev/null; then
        "$1"
    else
        echo "Game '$1' not found. You may need to install it first."
    fi
}

# List games grouped by category
list_games() {
    declare -A grouped
    for entry in "${games[@]}"; do
        IFS='|' read -r name category description apt <<< "$entry"
        # Append entry without extra dot at end of description.
        grouped["$category"]+="$name – $description (apt: $apt)\n"
    done

    for category in $(printf "%s\n" "${!grouped[@]}" | sort); do
        echo -e "\n# ${category} games"
        echo -e "${grouped[$category]}"
    done
}

# Main argument handling
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h)
            usage
            exit 0
            ;;
        -l)
            list_games
            exit 0
            ;;
        -i)
            install_game "$2"
            exit 0
            ;;
        -iall)
            install_all_games
            exit 0
            ;;
        -itype)
            install_by_type "$2"
            exit 0
            ;;
        -r)
            run_game "$2"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

usage
exit 1

