# Weekend Break Finder - Setup Guide

## Overview
This tool automatically searches for the best-priced weekend breaks across European cities by comparing flights, trains, and accommodation. It ranks destinations by total cost and filters by your criteria (direct flights only, no late departures, train journeys under 5 hours).

## Quick Start

### 1. Install Dependencies
```bash
pip install -r requirements.txt
```

### 2. Set Up API Keys (See detailed guide below)
Create a `.env` file in the same directory:
```bash
AMADEUS_API_KEY=your_key_here
AMADEUS_API_SECRET=your_secret_here
```

### 3. Run the Script
```bash
python weekend_break_finder.py
```

## API Setup Guide

### Flight Data: Amadeus API (Recommended - FREE)

The Amadeus Self-Service API provides excellent flight search capabilities with a generous free tier.

**Sign Up:**
1. Go to https://developers.amadeus.com/
2. Click "Register" (top right)
3. Create a free account
4. Once logged in, go to "My Self-Service Workspace"
5. Create a new app - you'll get your API Key and API Secret

**Free Tier Limits:**
- 2,000 free API calls per month
- More than enough for personal use!
- Test environment available (what this script uses by default)

**To Use Production Data:**
- In the script, change `test.api.amadeus.com` to `api.amadeus.com`
- Production gives you real bookable fares

### Accommodation Data: Options

**Option 1: Booking.com API (Partner Program)**
- Official but requires partnership approval
- Apply at: https://connect.booking.com/
- Best for commercial use

**Option 2: Rapid API - Booking.com Unofficial (Paid)**
- https://rapidapi.com/tipsters/api/booking-com/
- About €10-30/month depending on volume
- Easier to get started

**Option 3: Keep Using Estimates (Current)**
- The script includes reasonable price estimates for now
- Good enough to compare cities and spot deals
- Can manually verify top 3 results on Booking.com

**Option 4: Web Scraping (Advanced)**
- Use libraries like BeautifulSoup or Playwright
- Add delays to be respectful to servers
- Check Booking.com's terms of service

### Train Data: Options

**Option 1: Trainline API**
- https://www.trainline.com/
- Currently no public API, but you can contact them for partnership

**Option 2: Rail Europe API**
- https://www.raileurope.com/
- B2B focused, requires business account

**Option 3: Keep Using Estimates (Current)**
- Script includes estimates for major routes from Amsterdam
- Manually verify top options on trainline.com

**Option 4: Omio API**
- https://www.omio.com/
- Covers trains, buses, and flights
- No official public API yet

## Configuration

### Customizing Your Search

Edit these variables in `weekend_break_finder.py`:

```python
# In the main() function
ORIGIN_CITY = "Amsterdam"  # Your home city
OUTBOUND_DATE = "2025-11-14"  # Friday departure
RETURN_DATE = "2025-11-17"    # Monday return

# In the __init__ method
self.origin_code = "AMS"  # Airport code for Amsterdam
```

### Adding More Cities

Add to the `EUROPEAN_CITIES` list:

```python
EUROPEAN_CITIES = [
    {"name": "Barcelona", "country": "Spain", "code": "BCN"},
    {"name": "YourCity", "country": "YourCountry", "code": "XXX"},
    # ... more cities
]
```

Find airport codes (IATA codes) at: https://www.iata.org/en/publications/directories/code-search/

### Adjusting Filters

Modify these in the script:

```python
# No flights after 7pm
if hour >= 19:  # Change this number (24-hour format)
    continue

# Train journeys max 5 hours
if info["hours"] <= 5:  # Change this number
```

## Usage Examples

### Basic Usage
```bash
python weekend_break_finder.py
```

### With API Keys
```bash
# Set environment variables
export AMADEUS_API_KEY="your_key"
export AMADEUS_API_SECRET="your_secret"

python weekend_break_finder.py
```

### Or use a .env file
Create `.env`:
```
AMADEUS_API_KEY=your_key_here
AMADEUS_API_SECRET=your_secret_here
```

Then modify the script to load it:
```python
from dotenv import load_dotenv
load_dotenv()
```

## Output

The script produces:

1. **Console Output** - Ranked list of destinations with prices
2. **JSON File** - `weekend_breaks.json` with all details for further analysis

### Example Output
```
🏆 BEST WEEKEND BREAKS - RANKED BY TOTAL COST
================================================================================

1. Budapest, Hungary
   Transport: FLIGHT - €89.00
   Accommodation: €135.00
   💰 TOTAL: €224.00
   ✈️  W6 - Departs 2025-11-14T10:30:00
   🏨 Central Hotel Option 1
      Rating: 4.0 ⭐
      Location: 0.5km from center

2. Prague, Czech Republic
   Transport: FLIGHT - €95.00
   Accommodation: €150.00
   💰 TOTAL: €245.00
   ...
```

## Roadmap / Improvements

### Short Term
- [ ] Add more European cities (50+ destinations)
- [ ] Improve accommodation filtering (star ratings, reviews)
- [ ] Add weather data integration
- [ ] Email notifications for price drops

### Medium Term
- [ ] Full Booking.com API integration
- [ ] Real train API integration (Trainline/Omio)
- [ ] Web scraping fallback option
- [ ] GUI interface (Flask web app)

### Long Term
- [ ] Price tracking over time
- [ ] "Flexible dates" mode (±3 days)
- [ ] Multi-city trips
- [ ] Group bookings
- [ ] Activity suggestions per city

## Troubleshooting

### "Amadeus API credentials not found"
- Make sure you've set the environment variables
- Or create a .env file with your credentials

### "Flight search failed for XXX: 401"
- Your API token might have expired
- Check your Amadeus API key and secret are correct

### "No transport options found"
- Some cities might not have direct flights from your origin
- The Amadeus test environment has limited data
- Switch to production API for real results

### Script runs but prices seem off
- Accommodation prices are estimated by default
- Set up proper APIs for accurate pricing
- Manually verify top 3-5 results

## Tips for Best Results

1. **Run searches midweek** - Flight prices often update Tuesday/Wednesday
2. **Compare multiple weekends** - Run the script for 2-3 different weekends
3. **Book early** - Once you find a good deal, prices usually go up
4. **Set up price alerts** - Run this weekly and track changes
5. **Verify manually** - Always double-check the top 3 results on actual booking sites

## Cost Analysis

**Free Version (Current Setup):**
- ✅ Amadeus API: FREE (2,000 calls/month)
- ⚠️ Accommodation: Estimates only
- ⚠️ Trains: Estimates only
- **Perfect for**: Comparing cities and finding rough prices

**Paid Version (Full Integration):**
- ✅ Amadeus API: FREE
- 💰 Rapid API Booking.com: ~€20/month
- 💰 Train API: Varies (or keep estimates)
- **Total: ~€20-30/month**
- **Perfect for**: Accurate prices and automated booking

## Legal & Ethical Notes

- Respect API rate limits
- Don't abuse free tiers
- If web scraping, use reasonable delays
- Check terms of service for each API
- This tool is for personal use

## Questions?

This is a starting point! The beauty of having the code is you can customize it endlessly. Want to:
- Focus only on warm cities?
- Add a budget limit filter?
- Include weekend activities?
- Prioritize certain airlines?

Just modify the code - it's yours now! 🎉

---

**Happy travels! 🌍✈️**
