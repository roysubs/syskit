#!/usr/bin/env python3
# Author: Roy Wiseman 2025-03

import requests
import sys
import json
from datetime import datetime, timedelta, date, timezone
import argparse
import os
import configparser
from urllib.parse import urlencode

# --- Configuration & Constants ---
SCRIPT_BASENAME = os.path.splitext(os.path.basename(__file__))[0]
SCRIPT_NAME = os.path.basename(__file__)

CONFIG_FILE_NAME = f".{SCRIPT_BASENAME}"
CONFIG_FILE_PATH = os.path.join(os.path.expanduser("~"), CONFIG_FILE_NAME)

CONFIG = configparser.ConfigParser()

# ANSI escape codes
BRIGHT_WHITE, GREEN, RED, YELLOW, CYAN, MAGENTA, BLUE, RESET_COLOR, BOLD = \
    "\033[1;37m", "\033[0;32m", "\033[0;31m", "\033[0;33m", "\033[0;36m", \
    "\033[0;35m", "\033[0;34m", "\033[0m", "\033[1m"

# API Endpoints
IPINFO_URL = "https://ipinfo.io"
NOMINATIM_GEOCODE_URL = "https://nominatim.openstreetmap.org/search"
OPENCAGE_GEOCODE_URL = "https://api.opencagedata.com/geocode/v1/json"
TICKETMASTER_DISCOVERY_API_URL = "https://app.ticketmaster.com/discovery/v2/events.json"
EVENTBRITE_API_URL = "https://www.eventbriteapi.com/v3/events/search/"
OPENWEATHERMAP_URL = "https://api.openweathermap.org/data/2.5/weather"

CACHE_DIR = os.path.join(os.path.expanduser("~"), ".cache", SCRIPT_NAME)
os.makedirs(CACHE_DIR, exist_ok=True)

API_KEYS = {}
DEFAULTS = {}

# --- Helper Functions ---

def print_colored(text, color):
    print(f"{color}{text}{RESET_COLOR}")

def create_template_config(config_path):
    template_content = f"""\
# Configuration file for {SCRIPT_NAME}
# Please replace placeholder values with your actual API keys or Tokens.
# You can obtain free API keys from the respective services for personal use.

[API_KEYS]
# IP Geolocation (ipinfo.io - for location when none is specified)
IPINFO_KEY = YOUR_IPINFO_KEY_HERE

# Event Providers
TICKETMASTER_KEY = YOUR_TICKETMASTER_KEY_HERE
EVENTBRITE_KEY = YOUR_EVENTBRITE_OAUTH_KEY_HERE # Usually private

# Geocoding (opencagedata.com - for resolving named locations)
OPENCAGE_KEY = YOUR_OPENCAGE_KEY_HERE

# Weather (openweathermap.org - for the --weather option)
OPENWEATHERMAP_KEY = YOUR_OPENWEATHERMAP_KEY_HERE

[DEFAULTS]
# Default search radius in kilometers if not specified
DEFAULT_RADIUS_KM = 25
# Default number of days to look ahead for events (including today)
DEFAULT_DAYS_AHEAD = 7
# How long to keep API responses in cache (in seconds)
CACHE_DURATION_SECONDS = 3600
"""
    try:
        with open(config_path, 'w', encoding='utf-8') as f:
            f.write(template_content)
        print_colored(f"A template configuration file has been created at: {config_path}", GREEN)
        print_colored("Please edit it with your API keys and then re-run the script.", YELLOW)
    except IOError as e:
        print_colored(f"Error: Could not write template config file to {config_path}: {e}", RED)
        print_colored("Please create the file manually or check permissions.", RED)

def load_config():
    global API_KEYS, DEFAULTS
    if not os.path.exists(CONFIG_FILE_PATH):
        create_template_config(CONFIG_FILE_PATH)
        sys.exit(1)

    try:
        CONFIG.read(CONFIG_FILE_PATH)
    except configparser.Error as e:
        print_colored(f"Error parsing configuration file '{CONFIG_FILE_PATH}': {e}", RED)
        print_colored("Please ensure it follows the INI format with section headers like [API_KEYS].", RED)
        sys.exit(1)

    # Ensure API_KEYS and DEFAULTS dictionaries exist
    API_KEYS = dict(CONFIG['API_KEYS']) if 'API_KEYS' in CONFIG else {}
    DEFAULTS = dict(CONFIG['DEFAULTS']) if 'DEFAULTS' in CONFIG else {}

    if not API_KEYS: print_colored(f"Warning: [API_KEYS] section missing or empty in '{CONFIG_FILE_PATH}'. API-dependent features may fail.", YELLOW)
    if not DEFAULTS: print_colored(f"Warning: [DEFAULTS] section missing or empty in '{CONFIG_FILE_PATH}'. Using script defaults.", YELLOW)
    
    # Normalize keys from config to lowercase and ensure all expected API_KEYS have a default None
    api_keys_lower = {k.lower(): v for k, v in API_KEYS.items()}
    API_KEYS = {} # Reset and populate with lowercase and defaults
    for key_name in ['ipinfo_token', 'ticketmaster_api_key', 'eventbrite_token', 'opencage_api_key', 'openweathermap_api_key']:
        API_KEYS[key_name] = api_keys_lower.get(key_name, None)

    DEFAULTS.setdefault('default_radius_km', '25')
    DEFAULTS.setdefault('default_days_ahead', '7')
    DEFAULTS.setdefault('cache_duration_seconds', '3600')


def get_cache_path(filename_prefix, params_dict):
    param_str = "_".join(f"{k}_{v}" for k, v in sorted(params_dict.items()))
    return os.path.join(CACHE_DIR, f"{filename_prefix}_{param_str}.json")

def read_from_cache(cache_file, duration_seconds):
    if os.path.exists(cache_file):
        file_mod_time = os.path.getmtime(cache_file)
        if (datetime.now().timestamp() - file_mod_time) < duration_seconds:
            try:
                with open(cache_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except json.JSONDecodeError:
                print_colored(f"Warning: Corrupted cache file: {cache_file}", YELLOW)
    return None

def write_to_cache(cache_file, data):
    try:
        with open(cache_file, 'w', encoding='utf-8') as f:
            json.dump(data, f)
    except Exception as e:
        print_colored(f"Error writing to cache file {cache_file}: {e}", RED)

def fetch_data(url, params=None, headers=None, cache_filename_prefix=None, cache_params_for_filename=None):
    cache_duration = int(DEFAULTS.get('cache_duration_seconds', 3600))
    cache_file = None

    if cache_filename_prefix and cache_params_for_filename:
        cache_file = get_cache_path(cache_filename_prefix, cache_params_for_filename)
        cached_data = read_from_cache(cache_file, cache_duration)
        if cached_data:
            if ARGS.verbose: print_colored(f"Cache hit for {cache_filename_prefix}", BLUE)
            return cached_data

    try:
        if ARGS.verbose: print_colored(f"API Request: {url} with params {params}", BLUE)
        response = requests.get(url, params=params, headers=headers, timeout=15)
        response.raise_for_status()
        data = response.json()
        if cache_file:
            write_to_cache(cache_file, data)
        return data
    except requests.exceptions.Timeout:
        print_colored(f"Error: API request timed out for {url}.", RED)
    except requests.exceptions.HTTPError as e:
        error_msg = f"Error: API request failed for {url} with status {e.response.status_code}."
        try:
            error_details = e.response.json()
            error_msg += f" Details: {error_details}"
        except json.JSONDecodeError:
            error_msg += f" Details: {e.response.text[:200]}"
        print_colored(error_msg, RED)
        if e.response.status_code in [401, 403]:
            print_colored(f"This often indicates an invalid or missing API key. Check '{CONFIG_FILE_PATH}'.", YELLOW)
    except requests.exceptions.RequestException as e:
        print_colored(f"Error: API request failed for {url}: {e}", RED)
    except json.JSONDecodeError:
        print_colored(f"Error: Could not decode API response from {url} (not valid JSON).", RED)
    return None

def get_location_from_ip():
    print_colored("Attempting to determine location from IP address...", CYAN)
    token = API_KEYS.get('ipinfo_token')
    if not token or token == 'YOUR_IPINFO_TOKEN_HERE':
        print_colored(f"Warning: IPINFO_TOKEN not found or is placeholder in '{CONFIG_FILE_PATH}'. IP-based location will be limited.", YELLOW)
        try: data = fetch_data("https://ipapi.co/json/", cache_filename_prefix="ipapi_loc", cache_params_for_filename={"service": "ipapi"})
        except Exception: data = None
    else:
        url = f"{IPINFO_URL}/json?token={token}"
        data = fetch_data(url, cache_filename_prefix="ipinfo_loc", cache_params_for_filename={"token_present": "yes"})

    if data and 'loc' in data and 'city' in data and 'country' in data:
        lat, lon = map(float, data['loc'].split(','))
        city, country_name = data.get('city', 'Unknown City'), data.get('country', 'Unknown Country')
        print_colored(f"Location determined: {city}, {country_name} ({lat:.4f}, {lon:.4f})", GREEN)
        return {"latitude": lat, "longitude": lon, "city": city, "country": country_name, "name": f"{city}, {country_name}"}
    else:
        print_colored("Could not determine location from IP address.", RED)
        if data and ARGS.verbose: print_colored(f"IP Geolocation Response: {data}", YELLOW)
    return None

def geocode_location_name(location_name):
    print_colored(f"Attempting to geocode location: '{location_name}'...", CYAN)
    opencage_key = API_KEYS.get('opencage_api_key')
    if opencage_key and opencage_key != 'YOUR_OPENCAGE_API_KEY_HERE':
        params = {'q': location_name, 'key': opencage_key, 'limit': 1, 'no_annotations': 1}
        data = fetch_data(OPENCAGE_GEOCODE_URL, params=params, cache_filename_prefix="opencage_geocode", cache_params_for_filename={"q": location_name})
        if data and data.get('results'):
            res = data['results'][0]
            lat, lon, name = res['geometry']['lat'], res['geometry']['lng'], res.get('formatted', location_name)
            print_colored(f"Geocoded '{location_name}' to: {name} ({lat:.4f}, {lon:.4f})", GREEN)
            return {"latitude": lat, "longitude": lon, "name": name}
    else:
        print_colored(f"Warning: OPENCAGE_API_KEY not found/placeholder in '{CONFIG_FILE_PATH}'. Using Nominatim (rate limits apply).", YELLOW)
        headers = {'User-Agent': f'{SCRIPT_NAME}/1.0 ({os.getenv("USER", "user")}@example.com - for Nominatim ToS)'} # Be a good citizen
        params = {'q': location_name, 'format': 'json', 'limit': 1, 'addressdetails': 1}
        data = fetch_data(NOMINATIM_GEOCODE_URL, params=params, headers=headers, cache_filename_prefix="nominatim_geocode", cache_params_for_filename={"q": location_name})
        if data and len(data) > 0: # Nominatim returns a list
            res = data[0]
            lat, lon = float(res['lat']), float(res['lon'])
            name = res.get('display_name', location_name)
            print_colored(f"Geocoded '{location_name}' to: {name} ({lat:.4f}, {lon:.4f})", GREEN)
            return {"latitude": lat, "longitude": lon, "name": name,
                    "city": res.get('address', {}).get('city', res.get('address', {}).get('town', '')),
                    "country_code": res.get('address', {}).get('country_code', '').upper()}
    print_colored(f"Could not geocode location: '{location_name}'.", RED)
    return None

def format_event_datetime(dt_str):
    if not dt_str or dt_str == 'N/A': return "Date/Time N/A"
    try:
        # datetime.fromisoformat is quite robust for ISO 8601 strings
        dt_obj = datetime.fromisoformat(dt_str)
        # If dt_obj is naive, strftime formats it as local.
        # If dt_obj is aware, strftime includes offset/tz abbr.
        return dt_obj.strftime('%a, %b %d, %Y %I:%M %p %Z').strip().replace(" UTC", "Z") # Common UTC display
    except ValueError:
        # Fallback for date-only strings if fromisoformat failed (e.g. YYYY-MM-DD)
        try:
            dt_obj = datetime.strptime(dt_str, '%Y-%m-%d')
            return dt_obj.strftime('%a, %b %d, %Y (Full Day)')
        except ValueError:
            return dt_str # Return original if all parsing fails

def get_weather_forecast(lat, lon, city_name):
    openweathermap_key = API_KEYS.get('openweathermap_api_key')
    if not openweathermap_key or openweathermap_key == 'YOUR_OPENWEATHERMAP_API_KEY_HERE':
        return f" (Weather: API key missing/placeholder in '{CONFIG_FILE_PATH}')"
    params = {'lat': lat, 'lon': lon, 'appid': openweathermap_key, 'units': 'metric'}
    weather_data = fetch_data(OPENWEATHERMAP_URL, params=params, cache_filename_prefix="weather", cache_params_for_filename={"lat": str(lat)[:5], "lon": str(lon)[:5]})
    if weather_data and 'weather' in weather_data and 'main' in weather_data:
        desc = weather_data['weather'][0]['description']
        temp, feels = weather_data['main']['temp'], weather_data['main']['feels_like']
        return f" ({city_name} weather: {desc}, {temp}°C, feels like {feels}°C)"
    return f" (Weather for {city_name} unavailable)"

def fetch_ticketmaster_events(lat, lon, radius_km, start_datetime_iso, end_datetime_iso, keyword=None, classification_name=None):
    print_colored("\nFetching events from Ticketmaster...", MAGENTA)
    api_key = API_KEYS.get('ticketmaster_api_key')
    if not api_key or api_key == 'YOUR_TICKETMASTER_API_KEY_HERE':
        print_colored(f"Warning: TICKETMASTER_API_KEY not found/placeholder in '{CONFIG_FILE_PATH}'. Skipping Ticketmaster.", YELLOW)
        return []
    params = {
        'apikey': api_key, 'latlong': f"{lat},{lon}", 'radius': str(radius_km), 'unit': 'km',
        'startDateTime': start_datetime_iso, 'endDateTime': end_datetime_iso, 'sort': 'date,asc', 'size': 50 }
    if keyword: params['keyword'] = keyword
    if classification_name: params['classificationName'] = classification_name
    cache_params = {k:v for k,v in params.items() if k != 'apikey'}

    data = fetch_data(TICKETMASTER_DISCOVERY_API_URL, params=params, cache_filename_prefix="ticketmaster", cache_params_for_filename=cache_params)
    events = []
    if data and '_embedded' in data and 'events' in data['_embedded']:
        for event_data in data['_embedded']['events']:
            name = event_data.get('name', 'N/A')
            url = event_data.get('url', '#')
            start_info = event_data.get('dates', {}).get('start', {})
            datetime_str = start_info.get('dateTime') # Prefer this, often has TZ
            if not datetime_str: # Fallback
                local_date, local_time = start_info.get('localDate'), start_info.get('localTime')
                if local_date and local_time: datetime_str = f"{local_date}T{local_time}"
                elif local_date: datetime_str = local_date
                else: datetime_str = 'N/A'

            venue_info = event_data.get('_embedded', {}).get('venues', [{}])[0]
            venue_name = venue_info.get('name', 'N/A')
            venue_city = venue_info.get('city', {}).get('name', '')
            addr_parts = [venue_info.get('address',{}).get('line1',''), venue_city, venue_info.get('state',{}).get('name',''), venue_info.get('postalCode','')]
            venue_address = ", ".join(filter(None, addr_parts))
            v_lat, v_lon = venue_info.get('location',{}).get('latitude'), venue_info.get('location',{}).get('longitude')
            map_link = f"https://maps.google.com/?q={v_lat},{v_lon}" if v_lat and v_lon else ""
            category = (event_data.get('classifications',[{}])[0].get('segment',{}).get('name','Event') if event_data.get('classifications') else "Event")

            events.append({
                'source': 'Ticketmaster', 'name': name, 'datetime_str': datetime_str,
                'display_datetime': format_event_datetime(datetime_str), # Use unified formatter
                'venue_name': venue_name, 'venue_address': venue_address, 'url': url, 'category': category, 'map_link': map_link })
        print_colored(f"Found {len(events)} events from Ticketmaster.", MAGENTA)
    else:
        print_colored("No events found from Ticketmaster for the criteria.", MAGENTA)
        if ARGS.verbose and data: print_colored(f"Ticketmaster Response: {json.dumps(data, indent=2)}", BLUE)
    return events

def fetch_eventbrite_events(lat, lon, radius_km, start_date_iso, end_date_iso, keyword=None, categories=None):
    print_colored("\nFetching events from Eventbrite...", MAGENTA)
    token = API_KEYS.get('eventbrite_token')
    if not token or token == 'YOUR_EVENTBRITE_OAUTH_TOKEN_HERE':
        print_colored(f"Warning: EVENTBRITE_TOKEN not found/placeholder in '{CONFIG_FILE_PATH}'. Skipping Eventbrite.", YELLOW)
        return []
    headers = {'Authorization': f'Bearer {token}'}
    params = {
        'location.latitude': lat, 'location.longitude': lon, 'location.within': f"{radius_km}km",
        'start_date.range_start': start_date_iso + "T00:00:00Z", 'start_date.range_end': end_date_iso + "T23:59:59Z",
        'sort_by': 'date', 'expand': 'venue,category,format' }
    if keyword: params['q'] = keyword
    if categories: params['categories'] = ",".join(categories)
    cache_params = params.copy()

    data = fetch_data(EVENTBRITE_API_URL, params=params, headers=headers, cache_filename_prefix="eventbrite", cache_params_for_filename=cache_params)
    events = []
    if data and 'events' in data:
        for event_data in data['events']:
            name = event_data.get('name', {}).get('text', 'N/A')
            url = event_data.get('url', '#')
            start_datetime = event_data.get('start', {}).get('utc', 'N/A') # Eventbrite provides UTC
            venue_data = event_data.get('venue', {})
            venue_name = venue_data.get('name', 'Online or N/A') if venue_data else "Online or N/A"
            venue_addr_disp = "N/A"
            v_lat, v_lon = None, None
            if venue_data and venue_data.get('address') and venue_data['address'].get('localized_address_display'):
                venue_addr_disp = venue_data['address']['localized_address_display']
                v_lat, v_lon = venue_data.get('latitude'), venue_data.get('longitude')
            map_link = f"https://maps.google.com/?q={v_lat},{v_lon}" if v_lat and v_lon else ""
            category = event_data.get('category', {}).get('name', 'Event')

            events.append({
                'source': 'Eventbrite', 'name': name, 'datetime_str': start_datetime,
                'display_datetime': format_event_datetime(start_datetime), # Use unified formatter
                'venue_name': venue_name, 'venue_address': venue_addr_disp, 'url': url, 'category': category, 'map_link': map_link })
        print_colored(f"Found {len(events)} events from Eventbrite.", MAGENTA)
    else:
        print_colored("No events found from Eventbrite for the criteria.", MAGENTA)
        if ARGS.verbose and data: print_colored(f"Eventbrite Response: {json.dumps(data, indent=2)}", BLUE)
    return events

# --- Main Functions ---
def display_events(events, location_info, days_ahead_display, show_weather=False):
    if not events:
        print_colored("\nNo events found matching your criteria.", YELLOW)
        return

    print_colored(f"\n--- Events near {location_info['name']} (Next {days_ahead_display} day(s)) ---", BRIGHT_WHITE)

    def sort_key(event):
        dt_str = event.get('datetime_str')
        name_key = event.get('name', '').lower()
        if not dt_str or dt_str == 'N/A':
            return (datetime.max.replace(tzinfo=None), name_key)
        try:
            dt_obj = datetime.fromisoformat(dt_str)
        except ValueError:
            try: dt_obj = datetime.strptime(dt_str, '%Y-%m-%d')
            except ValueError:
                if ARGS.verbose: print_colored(f"Warning: Could not parse date '{dt_str}' for sorting '{name_key}'.", YELLOW)
                return (datetime.max.replace(tzinfo=None), name_key)
        if dt_obj.tzinfo is not None and dt_obj.tzinfo.utcoffset(dt_obj) is not None:
            return (dt_obj.astimezone(timezone.utc).replace(tzinfo=None), name_key)
        return (dt_obj, name_key)

    events.sort(key=sort_key)
    current_event_date_header = None
    weather_info_today = ""

    if show_weather:
        today_obj = date.today()
        for event in events:
            sort_dt_obj = sort_key(event)[0]
            if sort_dt_obj != datetime.max.replace(tzinfo=None) and sort_dt_obj.date() == today_obj:
                weather_info_today = get_weather_forecast(
                    location_info['latitude'], location_info['longitude'],
                    location_info.get('city', location_info['name']))
                break

    for event in events:
        event_dt_obj_for_grouping = sort_key(event)[0] # Naive datetime for grouping

        # For the 📅 Date Group Header:
        if event_dt_obj_for_grouping == datetime.max.replace(tzinfo=None):
            date_group_header = "Unknown Date"
        else:
            date_group_header = event_dt_obj_for_grouping.strftime('%a, %b %d, %Y')

        # For the 🕒 Time display for each event:
        # Use the pre-formatted event['display_datetime'] from format_event_datetime()
        display_datetime_str = event.get('display_datetime', '')
        time_part_for_event = ""

        if "(Full Day)" in display_datetime_str:
            time_part_for_event = "(Full Day)"
        elif display_datetime_str and display_datetime_str != "Date/Time N/A":
            # Try to extract the time part, which follows the year in '%a, %b %d, %Y TIME_PART'
            try:
                # Use the grouping datetime object to reliably get the year string
                year_str = event_dt_obj_for_grouping.strftime('%Y')
                # Find position of year in the display string
                year_pos = display_datetime_str.find(year_str)
                if year_pos != -1:
                    # Time part is everything after the year string
                    candidate_time = display_datetime_str[year_pos + len(year_str):].strip()
                    if candidate_time and candidate_time != "(Full Day)":
                        time_part_for_event = candidate_time
                    # If candidate_time is empty, it means display_datetime_str was just a date.
                # If year_pos == -1, display_datetime_str might be malformed or date only.
                # If no specific time extracted, and it's not a full day event, leave time_part_for_event empty.
            except Exception: # pylint: disable=broad-except
                if ARGS.verbose: print_colored(f"Could not extract time from '{display_datetime_str}'", YELLOW)
                time_part_for_event = "" # Fallback

        if date_group_header != current_event_date_header:
            day_header_txt = f"\n📅 {BOLD}{date_group_header}{RESET_COLOR}"
            if event_dt_obj_for_grouping != datetime.max.replace(tzinfo=None) and \
               event_dt_obj_for_grouping.date() == date.today() and weather_info_today:
                day_header_txt += f"{CYAN}{weather_info_today}{RESET_COLOR}"
            print_colored(day_header_txt, BRIGHT_WHITE)
            current_event_date_header = date_group_header

        print(f"  {YELLOW}{event['name']}{RESET_COLOR} ({CYAN}{event.get('category', 'Event')}{RESET_COLOR}) [{BLUE}{event['source']}{RESET_COLOR}]")
        if time_part_for_event: print(f"    🕒 {BOLD}{time_part_for_event}{RESET_COLOR}")
        print(f"    📍 {event['venue_name']} - {event.get('venue_address', 'Address N/A')}")
        if event.get('map_link'): print(f"    🗺️  Map: {event['map_link']}")
        print(f"    🔗 {event['url']}")

def generate_ics_calendar(events, filename="events.ics"):
    if not events:
        print_colored("No events to generate iCalendar file.", YELLOW)
        return
    ics_content = ["BEGIN:VCALENDAR", "VERSION:2.0", f"PRODID:-//{SCRIPT_NAME}//EN"]
    for event in events:
        try:
            dt_str = event.get('datetime_str')
            if not dt_str or dt_str == 'N/A': continue
            dt_obj_orig = datetime.fromisoformat(dt_str)
            dtstart_prefix, dtstart_ics = "", ""

            if dt_obj_orig.tzinfo is not None and dt_obj_orig.tzinfo.utcoffset(dt_obj_orig) is not None: # Aware
                dt_obj_utc = dt_obj_orig.astimezone(timezone.utc)
                dtstart_ics = dt_obj_utc.strftime("%Y%m%dT%H%M%SZ")
            elif 'T' not in dt_str and not (' ' in dt_str and ':' in dt_str) : # Naive and date only (no T and no "HH:MM" like space)
                 dt_obj_date_only = datetime.strptime(dt_str, '%Y-%m-%d') # fromisoformat should handle this too
                 dtstart_ics = dt_obj_date_only.strftime("%Y%m%d")
                 dtstart_prefix = ";VALUE=DATE"
            else: # Naive but has time (local floating time)
                 dtstart_ics = dt_obj_orig.strftime("%Y%m%dT%H%M%S") # No Z, floating

            uid = f"{datetime.utcnow().timestamp()}-{event['name'][:10].replace(' ', '')}@{event['source'].lower()}.com"
            ics_content.extend([
                "BEGIN:VEVENT", f"UID:{uid}", f"DTSTAMP:{datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')}",
                f"DTSTART{dtstart_prefix}:{dtstart_ics}",
                f"SUMMARY:{event['name']}",
                f"DESCRIPTION:Venue: {event['venue_name']} - {event.get('venue_address', 'N/A')}\\nLink: {event['url']}\\nSource: {event['source']}",
                f"LOCATION:{event['venue_name']}, {event.get('venue_address', 'N/A')}", f"URL:{event['url']}", "END:VEVENT" ])
        except Exception as e:
            if ARGS.verbose: print_colored(f"Skipping event '{event.get('name')}' for ICS due to error: {e}", YELLOW)
    ics_content.append("END:VCALENDAR")
    try:
        with open(filename, 'w', encoding='utf-8') as f: f.write("\n".join(ics_content))
        print_colored(f"\niCalendar file generated: {filename}", GREEN)
    except IOError as e: print_colored(f"Error writing iCalendar file {filename}: {e}", RED)

def print_usage():
    default_radius = DEFAULTS.get('default_radius_km', '25')
    default_days = DEFAULTS.get('default_days_ahead', '7')
    usage = f"""
{BRIGHT_WHITE}{BOLD}Usage: {SCRIPT_NAME} [LOCATION] [OPTIONS]{RESET_COLOR}

{CYAN}Description:{RESET_COLOR}
  Finds social events, festivals, concerts, etc., near a specified location or your current IP-based location.
  Events are sourced from various providers (API keys required in '{CONFIG_FILE_PATH}').

{CYAN}Arguments:{RESET_COLOR}
  {YELLOW}LOCATION{RESET_COLOR}            Optional. Location string (e.g., "glasgow, scotland", "rotterdam, nl", "90210").
                         If omitted, tries to use your IP address to find your location.

{CYAN}Options:{RESET_COLOR}
  {YELLOW}-r, --radius RADIUS_KM{RESET_COLOR} Search radius in kilometers. Default: {default_radius} km.
  {YELLOW}-d, --days DAYS_AHEAD{RESET_COLOR}  Number of days to look ahead. Default: {default_days} days.
  {YELLOW}-k, --keyword KEYWORD{RESET_COLOR}  Filter by keyword.
  {YELLOW}-t, --type TYPE{RESET_COLOR}        Filter by event type/classification.
  {YELLOW}--date YYYY-MM-DD{RESET_COLOR}   Show events for a specific date.
  {YELLOW}--today{RESET_COLOR}              Show events for today only.
  {YELLOW}--tomorrow{RESET_COLOR}           Show events for tomorrow only.
  {YELLOW}--format FORMAT{RESET_COLOR}      Output: 'text' (default), 'json', 'ics'.
  {YELLOW}--weather{RESET_COLOR}            Show brief weather forecast for today's events.
  {YELLOW}-s, --source SOURCES{RESET_COLOR} Comma-separated sources (e.g., ticketmaster,eventbrite).
  {YELLOW}-v, --verbose{RESET_COLOR}         Enable verbose output.
  {YELLOW}--clear-cache{RESET_COLOR}       Clear cached API responses.
  {YELLOW}-h, --help{RESET_COLOR}            Show this help message and exit.

{CYAN}Configuration:{RESET_COLOR}
  Place API keys and default settings in '{BOLD}{CONFIG_FILE_PATH}{RESET_COLOR}'.
  If the file doesn't exist, a template will be created on first run, and the script will exit.
  Example structure for '{CONFIG_FILE_PATH}':
    [API_KEYS]
    IPINFO_KEY = YOUR_IPINFO_KEY_HERE
    TICKETMASTER_KEY = YOUR_TICKETMASTER_KEY_HERE
    # ... other keys ...

    [DEFAULTS]
    DEFAULT_RADIUS_KM = {default_radius}
    DEFAULT_DAYS_AHEAD = {default_days}
    # ... other defaults ...

{CYAN}Examples:{RESET_COLOR}
  {GREEN}{SCRIPT_NAME}{RESET_COLOR}
  {GREEN}{SCRIPT_NAME} "Paris, France"{RESET_COLOR}
  {GREEN}{SCRIPT_NAME} "London" -r 50 -d 3{RESET_COLOR}
"""
    print(usage)

def clear_cache_action():
    if os.path.exists(CACHE_DIR):
        try:
            removed_count = 0
            for item in os.listdir(CACHE_DIR):
                item_path = os.path.join(CACHE_DIR, item)
                if os.path.isfile(item_path):
                    os.remove(item_path)
                    removed_count +=1
            print_colored(f"Cache cleared: {removed_count} files removed from {CACHE_DIR}", GREEN)
        except Exception as e: print_colored(f"Error clearing cache: {e}", RED)
    else: print_colored("Cache directory not found. Nothing to clear.", YELLOW)

# --- Main Execution ---
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=f"Find events nearby. Config: {CONFIG_FILE_PATH}", add_help=False)
    # Args definition remains same
    parser.add_argument("location", nargs='?', default=None)
    parser.add_argument("-r", "--radius", type=int)
    parser.add_argument("-d", "--days", type=int)
    parser.add_argument("-k", "--keyword", type=str)
    parser.add_argument("-t", "--type", dest="event_type", type=str)
    parser.add_argument("--date", type=str)
    parser.add_argument("--today", action="store_true")
    parser.add_argument("--tomorrow", action="store_true")
    parser.add_argument("--format", choices=['text', 'json', 'ics'], default='text')
    parser.add_argument("--weather", action="store_true")
    parser.add_argument("-s", "--source", type=str)
    parser.add_argument("--surprise-me", action="store_true")
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument("--clear-cache", action="store_true")
    parser.add_argument("-h", "--help", action="store_true")
    ARGS = parser.parse_args()

    load_config() # Creates template and exits if not found. Loads DEFAULTS for print_usage.

    if ARGS.help:
        print_usage()
        sys.exit(0)

    if ARGS.clear_cache:
        clear_cache_action()

    target_location_info = None
    if ARGS.location: target_location_info = geocode_location_name(ARGS.location)
    else: target_location_info = get_location_from_ip()

    if not target_location_info:
        print_colored("Could not determine a valid location. Exiting.", RED)
        sys.exit(1)

    radius_km = ARGS.radius if ARGS.radius is not None else int(DEFAULTS.get('default_radius_km', 25))
    start_date_obj, end_date_obj, days_ahead_display_val = date.today(), None, 0

    if ARGS.today:
        end_date_obj, days_ahead_display_val = start_date_obj, 1
    elif ARGS.tomorrow:
        start_date_obj = date.today() + timedelta(days=1)
        end_date_obj, days_ahead_display_val = start_date_obj, 1
    elif ARGS.date:
        try:
            specific_date_obj = datetime.strptime(ARGS.date, "%Y-%m-%d").date()
            start_date_obj, end_date_obj, days_ahead_display_val = specific_date_obj, specific_date_obj, 1
        except ValueError:
            print_colored("Error: Invalid date format for --date. Please use YYYY-MM-DD.", RED); sys.exit(1)
    else:
        days_param_val = ARGS.days if ARGS.days is not None else int(DEFAULTS.get('default_days_ahead', 7))
        end_date_obj = start_date_obj + timedelta(days=days_param_val - 1)
        days_ahead_display_val = days_param_val

    start_datetime_iso_tm = datetime.combine(start_date_obj, datetime.min.time()).strftime('%Y-%m-%dT%H:%M:%SZ')
    end_datetime_iso_tm = datetime.combine(end_date_obj, datetime.max.time().replace(microsecond=0)).strftime('%Y-%m-%dT%H:%M:%SZ')
    start_date_iso_eb, end_date_iso_eb = start_date_obj.strftime('%Y-%m-%d'), end_date_obj.strftime('%Y-%m-%d')

    all_events = []
    available_sources = {"ticketmaster": fetch_ticketmaster_events, "eventbrite": fetch_eventbrite_events}
    sources_to_query = []
    if ARGS.source:
        req_sources = [s.strip().lower() for s in ARGS.source.split(',')]
        for s_name in req_sources:
            if s_name in available_sources: sources_to_query.append(s_name)
            else: print_colored(f"Warning: Unknown source '{s_name}'. Ignoring.", YELLOW)
    else: sources_to_query = [k for k, v_func in available_sources.items() if API_KEYS.get(f"{k}_api_key") or API_KEYS.get(f"{k}_token")] # Auto-select if key exists (simple check)
    if not sources_to_query: sources_to_query = list(available_sources.keys()) # Fallback if no keys found this way

    if "ticketmaster" in sources_to_query:
        tm_events = fetch_ticketmaster_events(target_location_info['latitude'], target_location_info['longitude'], radius_km,
                                            start_datetime_iso_tm, end_datetime_iso_tm, ARGS.keyword, ARGS.event_type)
        all_events.extend(tm_events)
    if "eventbrite" in sources_to_query:
        eb_cat = None 
        if ARGS.event_type: print_colored(f"Note: Eventbrite type filtering ('{ARGS.event_type}') needs ID mapping.", BLUE)
        eb_events = fetch_eventbrite_events(target_location_info['latitude'], target_location_info['longitude'], radius_km,
                                           start_date_iso_eb, end_date_iso_eb, ARGS.keyword, eb_cat)
        all_events.extend(eb_events)

    if ARGS.surprise_me: print_colored("\n🎉 Surprise Me! (Conceptual - showing regular results).", MAGENTA)

    if ARGS.format == 'json':
        output_data = {
            "query": {"location_input": ARGS.location, "resolved_location": target_location_info, "radius_km": radius_km,
                      "start_date": start_date_obj.isoformat(), "end_date": end_date_obj.isoformat(),
                      "keyword": ARGS.keyword, "event_type": ARGS.event_type,},
            "event_count": len(all_events), "events": all_events }
        print(json.dumps(output_data, indent=2))
    elif ARGS.format == 'ics':
        city_file_part = target_location_info.get('city', SCRIPT_BASENAME).replace(' ', '_').lower()
        generate_ics_calendar(all_events, filename=f"events_{city_file_part}.ics")
    else:
        display_events(all_events, target_location_info, days_ahead_display_val, show_weather=ARGS.weather)

    print_colored(f"\n{CYAN}Data sourced from: {', '.join(sources_to_query) or 'N/A'}. Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}{RESET_COLOR}", CYAN)
