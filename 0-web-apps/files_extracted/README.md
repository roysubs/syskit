# 🌍 Weekend Break Finder

**Stop wasting hours comparing prices across cities - let AI do it for you!**

This tool automatically searches flights, trains, and accommodation across 20+ European cities, then ranks them by total cost. Get the best weekend break deals in minutes, not hours.

## ✨ Features

- ✅ Searches **20+ European cities** simultaneously
- ✈️ Finds **direct flights only** (no layovers!)
- 🚫 Filters out **late evening flights** (>7pm)
- 🚂 Includes **train options** (under 5 hours)
- 🏨 Checks accommodation in **city centers**
- 💰 Ranks by **total cost** (transport + hotel)
- 📊 Exports to **JSON and CSV** for further analysis
- 🎯 **Budget filtering** included

## 🚀 Quick Start

### Option 1: Demo Mode (No Setup Required!)

Just run it right now with estimated prices:

```bash
python weekend_break_finder_enhanced.py
```

This gives you realistic price estimates so you can compare cities instantly. Perfect for initial planning!

### Option 2: Real Prices (5-minute setup)

Get actual, bookable prices by setting up the free Amadeus API:

1. Sign up at https://developers.amadeus.com/ (free!)
2. Create an app and copy your API Key & Secret
3. Create `.env` file:
   ```
   AMADEUS_API_KEY=your_key_here
   AMADEUS_API_SECRET=your_secret_here
   ```
4. In the script, change `DEMO_MODE = False`
5. Run it!

See `SETUP_GUIDE.md` for detailed instructions.

## 📖 Usage Examples

### Basic Search
```python
python weekend_break_finder_enhanced.py
```
Searches for Nov 14-17 weekend from Amsterdam, budget up to €400.

### Customize Your Search

Edit the configuration in `weekend_break_finder_enhanced.py`:

```python
# Your home city
ORIGIN_CITY = "Amsterdam"

# Your travel dates
OUTBOUND_DATE = "2025-11-14"  # Friday
RETURN_DATE = "2025-11-17"    # Monday

# Budget limits (in EUR)
MIN_BUDGET = 0
MAX_BUDGET = 400  # Or float('inf') for no limit

# Use demo mode or real API
DEMO_MODE = True  # Set to False when you have API keys
```

### Example Output

```
🏆 BEST WEEKEND BREAKS - RANKED BY TOTAL COST

1. Krakow, Poland
   Transport: FLIGHT - €53.61
   Accommodation: €96.00 (32.00/night)
   💰 TOTAL: €149.61
   ✈️  KL - Departs 08:30
   🏨 Krakow Central Hotel
      ⭐ 4.0 rating
      📍 0.5km from center

2. Budapest, Hungary
   Transport: FLIGHT - €59.29
   Accommodation: €108.00 (36.00/night)
   💰 TOTAL: €167.29
   ✈️  FR - Departs 13:20
   🏨 Budapest Central Hotel
      ⭐ 4.0 rating
      📍 0.5km from center
...
```

## 📁 Output Files

The tool generates two files:

1. **weekend_breaks.json** - Full data in JSON format
2. **weekend_breaks.csv** - Easy to open in Excel/Google Sheets

Perfect for comparing options or sharing with travel buddies!

## 🎯 What Cities Are Searched?

Currently includes 20 popular European destinations:

🇪🇸 Barcelona, Valencia, Seville  
🇫🇷 Paris  
🇮🇹 Rome, Milan  
🇩🇪 Berlin, Munich  
🇨🇿 Prague  
🇭🇺 Budapest  
🇦🇹 Vienna  
🇵🇹 Lisbon, Porto  
🇩🇰 Copenhagen  
🇮🇪 Dublin  
🇧🇪 Brussels  
🇬🇧 Edinburgh  
🇸🇪 Stockholm  
🇵🇱 Krakow  
🇬🇷 Athens  

**Want to add more?** Just edit the `EUROPEAN_CITIES` list in the script!

## 🔧 Customization

### Add Your Favorite Cities
```python
EUROPEAN_CITIES = [
    {"name": "YourCity", "country": "YourCountry", "code": "XXX"},
    # Find airport codes at: https://www.iata.org/
]
```

### Change Flight Time Filters
```python
# In search_flights() method
if hour >= 19:  # Current: no flights after 7pm
    continue     # Change 19 to your preferred hour
```

### Adjust Train Journey Limits
```python
# In estimate_train_option() method
if info["hours"] <= 5:  # Current: max 5 hours
```

## 💡 Pro Tips

1. **Run it weekly** - Track price changes and spot deals
2. **Try flexible dates** - Change dates by ±1 day to see price differences
3. **Set budget limits** - Focus on what you can actually afford
4. **Export to CSV** - Easily compare in Excel or Google Sheets
5. **Demo mode first** - Get a feel for results before setting up APIs
6. **Book early** - Once you find a deal, prices usually go up!

## 🆚 Demo Mode vs Real API

| Feature | Demo Mode | Real API (Amadeus) |
|---------|-----------|-------------------|
| Setup Time | 0 minutes | 5 minutes |
| Price Accuracy | Estimated (±20%) | Real, bookable prices |
| Flight Times | Random realistic | Actual schedules |
| Airlines | Generic | Specific carriers |
| Best For | Initial comparison | Final decision |
| Cost | FREE | FREE (2,000 calls/month) |

**Recommendation:** Start with Demo Mode to compare cities, then switch to Real API for the top 3-5 options.

## 📋 Files Included

- `weekend_break_finder.py` - Original version (needs API keys)
- `weekend_break_finder_enhanced.py` - **USE THIS ONE!** Has demo mode
- `requirements.txt` - Python dependencies
- `SETUP_GUIDE.md` - Detailed setup instructions
- `README.md` - This file
- `.env.template` - Template for your API keys

## 🐛 Troubleshooting

**"No results found"**
- Check your budget limits aren't too restrictive
- Try different dates
- Some cities might genuinely be expensive that weekend!

**"API credentials not found"**
- Make sure you created the `.env` file
- Check you copied the keys correctly
- Try Demo Mode first to test everything works

**Script runs but prices seem weird**
- Demo Mode uses estimates - this is normal
- Set up real API for accurate prices
- Manually verify top 3 results on booking sites

## 🎉 What's Next?

Once you get comfortable with the basic tool, you can:

1. Add more cities (easy!)
2. Integrate real accommodation APIs
3. Add train API for accurate rail prices
4. Create a web interface (Flask/Django)
5. Set up email alerts for price drops
6. Add weather data to help decide
7. Include weekend activities/events

## 🤝 Contributing Ideas

Have ideas to make this better? Some possibilities:

- Multi-city trips
- Group bookings calculator  
- "Flexible dates" mode (±3 days)
- Mobile app version
- Price history tracking
- Integration with Google Calendar
- Automatic booking (advanced!)

## 📄 License

This is your tool now - use it however you like! Modify, share, improve.

## ⚠️ Legal Stuff

- Respect API rate limits
- This tool is for personal use
- Always verify prices on official booking sites before purchasing
- Flight and accommodation prices change constantly

---

**Happy travels! 🌍✈️🎒**

*Questions? Check out SETUP_GUIDE.md for more details.*
