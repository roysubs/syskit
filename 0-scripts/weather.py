#!/usr/bin/env python3
# Author: Roy Wiseman 2025-02

import requests
import sys
import json
from datetime import datetime

# ANSI escape codes for colors
BRIGHT_WHITE = "\033[1;37m"
RESET_COLOR = "\033[0m"

USAGE_LINE = f"{BRIGHT_WHITE}Usage: weather.py [location] [-1|-2|-3 for days of text output | -json for JSON data]{RESET_COLOR}"
USAGE_LINE_DEFAULT_GRAPHICAL = f"{BRIGHT_WHITE} (Default: graphical view for current location if no options given){RESET_COLOR}"


def print_usage():
    print(USAGE_LINE)
    print(USAGE_LINE_DEFAULT_GRAPHICAL)

def get_current_location():
    """Tries to get the current location based on IP address."""
    try:
        response = requests.get("http://ip-api.com/json/?fields=city,country,status,message", timeout=5)
        response.raise_for_status()
        data = response.json()
        if data.get("status") == "success" and data.get("city"):
            return f"{data['city']}, {data['country']}"
        else:
            # Do not print error here, handle it in the main logic
            return None
    except: # Catch all exceptions for simplicity in this helper
        return None

def get_weather_ascii_art(location_query):
    """Fetches and displays weather from wttr.in in ASCII art format."""
    if not location_query:
        location_query = get_current_location()
        if not location_query:
            print(f"{BRIGHT_WHITE}Could not auto-detect location for ASCII view. Please specify one.{RESET_COLOR}")
            return
        print(f"{BRIGHT_WHITE}Fetching ASCII weather for auto-detected: {location_query}...{RESET_COLOR}")
    else:
        print(f"{BRIGHT_WHITE}Fetching ASCII weather for: {location_query}...{RESET_COLOR}")

    url = f"http://wttr.in/{location_query}"
    headers = {"Accept-Language": "en-US,en;q=0.5"}
    try:
        response = requests.get(url, headers=headers, timeout=15)
        response.raise_for_status()
        print(response.text)
    except requests.exceptions.Timeout:
        print(f"{BRIGHT_WHITE}Error: Request timed out for {location_query}.{RESET_COLOR}")
    except requests.exceptions.RequestException as e:
        print(f"{BRIGHT_WHITE}Error fetching ASCII weather for {location_query}: {e}{RESET_COLOR}")
    except Exception as e:
        print(f"{BRIGHT_WHITE}An unexpected error occurred: {e}{RESET_COLOR}")


def get_weather_text_details(location_query, forecast_days):
    """Fetches and displays detailed text weather information."""
    resolved_location = location_query
    if not resolved_location:
        resolved_location = get_current_location()
        if not resolved_location:
            print(f"{BRIGHT_WHITE}Could not auto-detect location. Please specify one.{RESET_COLOR}")
            return
        print(f"{BRIGHT_WHITE}Fetching detailed weather for auto-detected: {resolved_location}...{RESET_COLOR}")
    else:
        print(f"{BRIGHT_WHITE}Fetching detailed weather for: {resolved_location}...{RESET_COLOR}")

    url = f"http://wttr.in/{resolved_location}?format=j1"
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        weather_data = response.json()

        current_condition = weather_data.get('current_condition', [{}])[0]
        area = weather_data.get('nearest_area', [{}])[0]
        
        place_name_list = area.get('areaName', [])
        region_list = area.get('region', [])
        country_list = area.get('country', [])

        place_disp = place_name_list[0].get('value', 'N/A') if place_name_list else resolved_location.split(',')[0]
        region_disp = region_list[0].get('value', '') if region_list else ''
        country_disp = country_list[0].get('value', '') if country_list else ''
        
        display_loc = f"{place_disp}"
        if region_disp and region_disp != place_disp: display_loc += f", {region_disp}"
        if country_disp and country_disp not in display_loc : display_loc += f", {country_disp}"

        print(f"\n{BRIGHT_WHITE}Weather for: {display_loc}{RESET_COLOR}")
        print(f"Condition:     {current_condition.get('weatherDesc', [{}])[0].get('value', 'N/A')}")
        print(f"Temperature:   {current_condition.get('temp_C', 'N/A')}°C (Feels like: {current_condition.get('FeelsLikeC', 'N/A')}°C)")
        print(f"Humidity:      {current_condition.get('humidity', 'N/A')}%")
        print(f"Wind:          {current_condition.get('windspeedKmph', 'N/A')} km/h {current_condition.get('winddir16Point', 'N/A')}")
        # ... (add other current condition details as needed) ...

        available_forecast = weather_data.get('weather', [])
        days_to_show = min(forecast_days, len(available_forecast))

        if days_to_show > 0:
            print(f"\n{BRIGHT_WHITE}--- {days_to_show}-Day Detailed Forecast ---{RESET_COLOR}")
        for i in range(days_to_show):
            day_fc = available_forecast[i]
            date_obj = datetime.strptime(day_fc.get('date'), '%Y-%m-%d')
            day_name = "Today" if i == 0 else ("Tomorrow" if i == 1 else date_obj.strftime('%A, %b %d'))
            
            print(f"\n{BRIGHT_WHITE}{day_name} ({day_fc.get('date')}):{RESET_COLOR}")
            print(f"  Avg Temp:    {day_fc.get('avgtempC', 'N/A')}°C (Min: {day_fc.get('mintempC', 'N/A')}°C, Max: {day_fc.get('maxtempC', 'N/A')}°C)")
            print(f"  Sunrise:     {day_fc.get('astronomy', [{}])[0].get('sunrise', 'N/A')}")
            print(f"  Sunset:      {day_fc.get('astronomy', [{}])[0].get('sunset', 'N/A')}")
            
            print("  Hourly Summary:")
            for hour_data in day_fc.get('hourly', []):
                time_formatted = f"{int(hour_data.get('time', '0'))//100:02}:00"
                # Show only a few key hours or summarize if needed
                if int(hour_data.get('time', '0')) % 300 == 0: # e.g. 00:00, 03:00, 06:00 etc.
                     print(f"    {time_formatted}: {hour_data.get('tempC', 'N/A')}°C, {hour_data.get('weatherDesc', [{}])[0].get('value', 'N/A')}, Rain: {hour_data.get('chanceofrain', 'N/A')}%")

    except requests.exceptions.Timeout:
        print(f"{BRIGHT_WHITE}Error: Request for detailed weather timed out for {resolved_location}.{RESET_COLOR}")
    except requests.exceptions.RequestException as e:
        print(f"{BRIGHT_WHITE}Error fetching detailed weather for {resolved_location}: {e}{RESET_COLOR}")
    except json.JSONDecodeError:
        print(f"{BRIGHT_WHITE}Error: Could not parse weather data for {resolved_location}. Location might be invalid.{RESET_COLOR}")
    except Exception as e:
        print(f"{BRIGHT_WHITE}An unexpected error occurred: {e}{RESET_COLOR}")

def get_raw_json_data(location_query):
    """Fetches and prints the raw JSON data from wttr.in."""
    resolved_location = location_query
    if not resolved_location:
        resolved_location = get_current_location()
        if not resolved_location:
            print(f"{BRIGHT_WHITE}Could not auto-detect location for JSON data. Please specify one.{RESET_COLOR}")
            return
        print(f"{BRIGHT_WHITE}Fetching JSON data for auto-detected: {resolved_location}...{RESET_COLOR}")
    else:
        print(f"{BRIGHT_WHITE}Fetching JSON data for: {resolved_location}...{RESET_COLOR}")

    url = f"http://wttr.in/{resolved_location}?format=j1"
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        # Pretty print the JSON
        parsed_json = response.json()
        print(json.dumps(parsed_json, indent=2)) 
    except requests.exceptions.Timeout:
        print(f"{BRIGHT_WHITE}Error: Request for JSON data timed out for {resolved_location}.{RESET_COLOR}")
    except requests.exceptions.RequestException as e:
        print(f"{BRIGHT_WHITE}Error fetching JSON data for {resolved_location}: {e}{RESET_COLOR}")
    except json.JSONDecodeError:
        # This case means the raw response was not JSON, which wttr.in might do for invalid locations
        print(f"{BRIGHT_WHITE}Error: Response from server was not valid JSON. Location might be invalid.{RESET_COLOR}")
        print(f"Raw response was:\n{response.text[:500]}...") # Print first 500 chars of bad response
    except Exception as e:
        print(f"{BRIGHT_WHITE}An unexpected error occurred: {e}{RESET_COLOR}")


if __name__ == "__main__":
    print_usage() # Print usage every time

    args = sys.argv[1:]
    
    mode = 'ascii_art' # Default mode
    days_text_output = 3 # Default for ascii mode, not explicitly used but implies full view
    output_raw_json = False
    location_parts = []

    for arg in args:
        if arg in ['-1', '-2', '-3']:
            mode = 'text_details'
            days_text_output = int(arg[1:])
        elif arg == '-json':
            mode = 'raw_json'
        else:
            location_parts.append(arg)
    
    location_input = " ".join(location_parts) if location_parts else None

    if mode == 'ascii_art':
        get_weather_ascii_art(location_input)
    elif mode == 'text_details':
        get_weather_text_details(location_input, days_text_output)
    elif mode == 'raw_json':
        get_raw_json_data(location_input)
