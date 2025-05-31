#!/usr/bin/env python3
# Author: Roy Wiseman 2025-03

import requests
import sys
import json
from datetime import datetime, timedelta
import argparse

# --- Configuration ---
# Easily modifiable default list of cryptocurrencies (use CoinGecko IDs)
# Find IDs at coingecko.com (e.g., search Bitcoin, URL will be coingecko.com/en/coins/bitcoin)
DEFAULT_CRYPTO_IDS = ['bitcoin', 'ethereum', 'tether', 'binancecoin', 'ripple', 'dogecoin', 'solana', 'cardano']
# Mapping for common symbols to CoinGecko IDs (add more as needed)
SYMBOL_TO_ID_MAP = {
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'USDT': 'tether',
    'BNB': 'binancecoin',
    'XRP': 'ripple',
    'DOGE': 'dogecoin',
    'SOL': 'solana',
    'ADA': 'cardano',
    'DOT': 'polkadot',
    'AVAX': 'avalanche-2', # Avalanche's ID on CoinGecko
    'SHIB': 'shiba-inu',
    'TRX': 'tron',
    'LINK': 'chainlink',
    'MATIC': 'matic-network', # Polygon (MATIC)
    'LTC': 'litecoin',
    'XLM': 'stellar',
    'ATOM': 'cosmos',
    # Add more mappings if you frequently use symbols not matching IDs
}
API_BASE_URL = "https://api.coingecko.com/api/v3"
VS_CURRENCY = "usd" # Versus currency for prices

# ANSI escape codes for colors (optional, for better readability)
BRIGHT_WHITE = "\033[1;37m"
GREEN = "\033[0;32m"
RED = "\033[0;31m"
YELLOW = "\033[0;33m"
CYAN = "\033[0;36m"
RESET_COLOR = "\033[0m"

# --- Helper Functions ---
def print_usage():
    usage = f"""
{BRIGHT_WHITE}Usage: crypto.py [COMMA_SEP_SYMBOLS] [-d DAYS] [-e]{RESET_COLOR}

{CYAN}Arguments:{RESET_COLOR}
  {YELLOW}COMMA_SEP_SYMBOLS{RESET_COLOR}  Optional. Comma-separated crypto symbols (e.g., BTC,ETH,SOL).
                        Defaults to a predefined list if not provided.
  {YELLOW}-d DAYS, --days DAYS{RESET_COLOR} Optional. Show price X days ago and +/- change since then.
  {YELLOW}-e, --extended{RESET_COLOR}     Optional. Show extended information (Market Cap, Volume, ATH etc.).

{CYAN}Examples:{RESET_COLOR}
  {GREEN}crypto.py{RESET_COLOR}                   # Default coins, basic info
  {GREEN}crypto.py BTC,ETH{RESET_COLOR}           # Basic info for Bitcoin and Ethereum
  {GREEN}crypto.py SOL -d 7{RESET_COLOR}          # Solana price 7 days ago and now, with change
  {GREEN}crypto.py DOGE -e{RESET_COLOR}           # Extended info for Dogecoin
  {GREEN}crypto.py ADA,DOT -d 30 -e{RESET_COLOR}   # Cardano & Polkadot: 30-day history & extended info
"""
    print(usage)

def get_coingecko_ids(symbols_str):
    if not symbols_str:
        return DEFAULT_CRYPTO_IDS
    
    symbols = [s.strip().upper() for s in symbols_str.split(',')]
    ids = []
    for s in symbols:
        if s in SYMBOL_TO_ID_MAP:
            ids.append(SYMBOL_TO_ID_MAP[s])
        else:
            # Fallback: try using the lowercase symbol as ID if not in map
            # This works for many coins (e.g. "monero" for XMR if XMR not in map)
            ids.append(s.lower()) 
            print(f"{YELLOW}Warning: Symbol '{s}' not in predefined map. Trying '{s.lower()}' as ID.{RESET_COLOR}")
    return ids

def format_price(price):
    if price is None: return "N/A"
    if price < 0.01 and price != 0:
        return f"${price:.8f}" # For very small value coins
    return f"${price:,.2f}"

def format_percentage(change):
    if change is None: return "N/A"
    color = GREEN if change >= 0 else RED
    return f"{color}{change:+.2f}%{RESET_COLOR}"

def format_large_number(num):
    if num is None: return "N/A"
    if num >= 1_000_000_000_000:
        return f"${num/1_000_000_000_000:.2f}T"
    if num >= 1_000_000_000:
        return f"${num/1_000_000_000:.2f}B"
    if num >= 1_000_000:
        return f"${num/1_000_000:.2f}M"
    return f"${num:,.0f}"
    
def fetch_data(endpoint, params=None):
    try:
        response = requests.get(f"{API_BASE_URL}/{endpoint}", params=params, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.Timeout:
        print(f"{RED}Error: API request timed out.{RESET_COLOR}")
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 429:
            print(f"{RED}Error: API rate limit likely exceeded. Please wait and try again.{RESET_COLOR}")
        elif e.response.status_code == 404:
            print(f"{RED}Error: One or more coin IDs not found on CoinGecko. ({e.response.url}){RESET_COLOR}")
        else:
            print(f"{RED}Error: API request failed with status {e.response.status_code}. ({e.response.url}){RESET_COLOR}")
            try:
                print(f"       {e.response.json().get('error', '')}") # Show CoinGecko error if available
            except:
                pass # Ignore if error response is not JSON
    except requests.exceptions.RequestException as e:
        print(f"{RED}Error: API request failed: {e}{RESET_COLOR}")
    except json.JSONDecodeError:
        print(f"{RED}Error: Could not decode API response (not valid JSON).{RESET_COLOR}")
    return None

# --- Main Functions ---
def display_basic_info(crypto_ids):
    print(f"\n{CYAN}Fetching current market data...{RESET_COLOR}")
    params = {
        'ids': ','.join(crypto_ids),
        'vs_currency': VS_CURRENCY,
        'order': 'market_cap_desc',
        'per_page': len(crypto_ids),
        'page': 1,
        'sparkline': 'false',
        'price_change_percentage': '1h,24h,7d' # Request these for basic view too
    }
    data = fetch_data("coins/markets", params)

    if not data:
        return

    print(f"\n{BRIGHT_WHITE}--- Current Crypto Prices (vs {VS_CURRENCY.upper()}) ---{RESET_COLOR}")
    for coin in data:
        name = coin.get('name', 'N/A')
        symbol = coin.get('symbol', 'N/A').upper()
        current_price = coin.get('current_price')
        high_24h = coin.get('high_24h')
        low_24h = coin.get('low_24h')
        price_change_24h_val = coin.get('price_change_24h')
        price_change_24h_pct = coin.get('price_change_percentage_24h')
        # last_updated = datetime.fromisoformat(coin.get('last_updated').replace('Z', '+00:00')).strftime('%Y-%m-%d %H:%M:%S %Z') if coin.get('last_updated') else "N/A"


        print(f"\n{YELLOW}{name} ({symbol}){RESET_COLOR}")
        print(f"  Price: {BRIGHT_WHITE}{format_price(current_price)}{RESET_COLOR}")
        print(f"  24h High: {format_price(high_24h)} | 24h Low: {format_price(low_24h)}")
        if price_change_24h_val is not None:
            change_color = GREEN if price_change_24h_val >= 0 else RED
            print(f"  24h Change: {change_color}{format_price(price_change_24h_val)}{RESET_COLOR} ({format_percentage(price_change_24h_pct)})")
        # print(f"  Last Updated: {last_updated}")


def display_extended_info(crypto_ids):
    print(f"\n{CYAN}Fetching extended market data...{RESET_COLOR}")
    params = {
        'ids': ','.join(crypto_ids),
        'vs_currency': VS_CURRENCY,
        'order': 'market_cap_desc',
        'per_page': len(crypto_ids),
        'page': 1,
        'sparkline': 'false',
        'price_change_percentage': '1h,24h,7d,30d' # Get more granular price changes
    }
    data = fetch_data("coins/markets", params)

    if not data:
        return

    print(f"\n{BRIGHT_WHITE}--- Extended Crypto Information (vs {VS_CURRENCY.upper()}) ---{RESET_COLOR}")
    for coin in data:
        name = coin.get('name', 'N/A')
        symbol = coin.get('symbol', 'N/A').upper()
        current_price = coin.get('current_price')
        market_cap = coin.get('market_cap')
        total_volume_24h = coin.get('total_volume')
        circulating_supply = coin.get('circulating_supply')
        total_supply = coin.get('total_supply')
        max_supply = coin.get('max_supply')
        ath = coin.get('ath')
        ath_change_percentage = coin.get('ath_change_percentage')
        # ath_date_str = coin.get('ath_date')
        # ath_date = datetime.fromisoformat(ath_date_str.replace('Z', '+00:00')).strftime('%Y-%m-%d') if ath_date_str else "N/A"
        
        price_change_1h_pct = coin.get('price_change_percentage_1h_in_currency')
        price_change_24h_pct = coin.get('price_change_percentage_24h_in_currency')
        price_change_7d_pct = coin.get('price_change_percentage_7d_in_currency')
        price_change_30d_pct = coin.get('price_change_percentage_30d_in_currency')

        print(f"\n{YELLOW}{name} ({symbol}){RESET_COLOR} - Price: {BRIGHT_WHITE}{format_price(current_price)}{RESET_COLOR}")
        print(f"  Market Cap: {format_large_number(market_cap)} (Rank: #{coin.get('market_cap_rank', 'N/A')})")
        print(f"  24h Volume: {format_large_number(total_volume_24h)}")
        print(f"  Circulating Supply: {circulating_supply:,.0f} {symbol}" if circulating_supply else "  Circulating Supply: N/A")
        if total_supply: print(f"  Total Supply: {total_supply:,.0f} {symbol}")
        if max_supply: print(f"  Max Supply: {max_supply:,.0f} {symbol}")
        
        print(f"  ATH: {format_price(ath)} ({format_percentage(ath_change_percentage)} from ATH)") # Date: {ath_date}
        
        print(f"  Price Change %:  1h: {format_percentage(price_change_1h_pct)} | "
              f"24h: {format_percentage(price_change_24h_pct)} | "
              f"7d: {format_percentage(price_change_7d_pct)} | "
              f"30d: {format_percentage(price_change_30d_pct)}")


def display_historical_info(crypto_ids, num_days_ago):
    print(f"\n{CYAN}Fetching current and historical data ({num_days_ago} days ago)...{RESET_COLOR}")
    
    # 1. Fetch current prices first
    current_prices_map = {}
    current_data_params = {
        'ids': ','.join(crypto_ids),
        'vs_currencies': VS_CURRENCY
    }
    current_data = fetch_data("simple/price", current_data_params)
    if not current_data:
        print(f"{RED}Could not fetch current prices. Aborting historical comparison.{RESET_COLOR}")
        return

    for coin_id in crypto_ids:
        if coin_id in current_data and VS_CURRENCY in current_data[coin_id]:
            current_prices_map[coin_id] = current_data[coin_id][VS_CURRENCY]
        else:
            current_prices_map[coin_id] = None # Mark as not found

    # 2. Fetch historical prices
    target_date_dt = datetime.now() - timedelta(days=num_days_ago)
    date_str_coingecko = target_date_dt.strftime('%d-%m-%Y') # dd-mm-yyyy format for CoinGecko history

    print(f"\n{BRIGHT_WHITE}--- Crypto Prices: Now vs. {num_days_ago} days ago ({target_date_dt.strftime('%Y-%m-%d')}) ---{RESET_COLOR}")

    for coin_id in crypto_ids:
        # Get original symbol if possible for display
        original_symbol = "N/A"
        for sym, c_id in SYMBOL_TO_ID_MAP.items():
            if c_id == coin_id:
                original_symbol = sym
                break
        if original_symbol == "N/A": # if not found in map, assume id is symbol-like
             original_symbol = coin_id.upper()


        current_price = current_prices_map.get(coin_id)
        if current_price is None:
            print(f"\n{YELLOW}{original_symbol} ({coin_id}){RESET_COLOR}")
            print(f"  Could not fetch current price data.")
            continue

        print(f"\n{YELLOW}{original_symbol} ({coin_id}){RESET_COLOR}")
        print(f"  Current Price: {BRIGHT_WHITE}{format_price(current_price)}{RESET_COLOR}")

        history_data = fetch_data(f"coins/{coin_id}/history", params={'date': date_str_coingecko})
        
        if history_data and 'market_data' in history_data and 'current_price' in history_data['market_data'] \
           and VS_CURRENCY in history_data['market_data']['current_price']:
            
            past_price = history_data['market_data']['current_price'][VS_CURRENCY]
            print(f"  Price on {date_str_coingecko}: {format_price(past_price)}")

            if past_price is not None and past_price != 0 and current_price is not None:
                change_val = current_price - past_price
                change_pct = (change_val / past_price) * 100
                change_color = GREEN if change_val >= 0 else RED
                
                print(f"  Change since {date_str_coingecko}: {change_color}{format_price(change_val)}{RESET_COLOR} ({format_percentage(change_pct)})")
            else:
                print(f"  Could not calculate change (missing data or past price was zero).")
        else:
            print(f"  Could not fetch or parse historical price data for {date_str_coingecko}.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Crypto Price Checker", add_help=False) # add_help=False to use custom usage
    parser.add_argument("symbols", nargs='?', default=None, help="Comma-separated crypto symbols (e.g., BTC,ETH,SOL)")
    parser.add_argument("-d", "--days", type=int, help="Show price X days ago and +/- change since then.")
    parser.add_argument("-e", "--extended", action="store_true", help="Show extended information.")
    parser.add_argument("-h", "--help", action="store_true", help="Show this help message and exit.")


    if "-h" in sys.argv or "--help" in sys.argv: # Custom help handling
        print_usage()
        sys.exit(0)

    args = parser.parse_args()
    
    if len(sys.argv) == 1 and not args.symbols: # If only script name is run, print usage then proceed with defaults
        print_usage() 
        # Then proceed to default execution

    crypto_ids_to_fetch = get_coingecko_ids(args.symbols)

    if not crypto_ids_to_fetch:
        print(f"{RED}No valid crypto IDs to fetch. Exiting.{RESET_COLOR}")
        sys.exit(1)

    # Determine mode based on arguments
    if args.days is not None:
        display_historical_info(crypto_ids_to_fetch, args.days)
        # If historical and extended are both requested, show extended for current data after historical
        if args.extended:
             print(f"\n{CYAN}--- Also showing extended info for current data ---{RESET_COLOR}")
             display_extended_info(crypto_ids_to_fetch) # Show extended for current data too
    elif args.extended:
        display_extended_info(crypto_ids_to_fetch) # Show basic info first then extended
    else:
        display_basic_info(crypto_ids_to_fetch)
    
    print(f"\n{CYAN}Data sourced from CoinGecko API. All prices in {VS_CURRENCY.upper()}.{RESET_COLOR}")
    print(f"{CYAN}Current time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}{RESET_COLOR}")
