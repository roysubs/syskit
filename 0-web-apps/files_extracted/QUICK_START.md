# 🚀 Quick Start Visual Guide

## Your Workflow in 3 Steps

```
┌─────────────────────────────────────────────────────────────┐
│  STEP 1: Install (30 seconds)                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  $ pip install -r requirements.txt                          │
│                                                              │
│  That's it! ✅                                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  STEP 2: Run It (2 minutes)                                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  $ python weekend_break_finder_enhanced.py                  │
│                                                              │
│  🔍 Searching 20+ cities...                                 │
│  ✓ Barcelona €262                                           │
│  ✓ Paris €295                                               │
│  ✓ Krakow €149  ← Best deal!                               │
│  ...                                                         │
│                                                              │
│  💾 Results saved to weekend_breaks.json                    │
│  📊 Results exported to weekend_breaks.csv                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  STEP 3: Pick Your Destination! 🎉                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Krakow    €149  ⭐ BEST VALUE                           │
│  2. Budapest  €167                                           │
│  3. Prague    €190                                           │
│  ...                                                         │
│                                                              │
│  Book the top option and enjoy! 🌍                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## What Happens Behind The Scenes

```
YOU INPUT:                    SCRIPT DOES:                   YOU GET:
┌──────────┐                 ┌──────────────┐              ┌──────────┐
│  Dates   │                 │   Search     │              │ Ranked   │
│ Nov 14-17│────────────────▶│   20+ Cities │─────────────▶│  List    │
│          │                 │              │              │          │
│ Budget   │                 │  ✓ Flights   │              │ €149-300 │
│  €0-400  │                 │  ✓ Trains    │              │          │
│          │                 │  ✓ Hotels    │              │ JSON +   │
│ Home:    │                 │              │              │ CSV      │
│Amsterdam │                 │  Filter &    │              │ Export   │
└──────────┘                 │  Rank        │              └──────────┘
                             └──────────────┘
```

## Demo Mode vs Real API Mode

```
┌───────────────────────────────┬────────────────────────────────┐
│      DEMO MODE (Default)      │    REAL API MODE (Optional)    │
├───────────────────────────────┼────────────────────────────────┤
│                               │                                │
│  ⚡ Works immediately          │  🔑 Requires API keys          │
│  📊 Estimated prices          │  💯 Real bookable prices       │
│  🆓 100% free                 │  🆓 Still free!                │
│  ⏱️  2 minutes                 │  ⏱️  2 minutes                 │
│  ✓ Great for comparing cities │  ✓ Great for final decision    │
│                               │                                │
│  USE THIS FIRST! ────────────▶│  UPGRADE LATER IF WANTED       │
│                               │                                │
└───────────────────────────────┴────────────────────────────────┘
```

## File Structure

```
weekend-break-finder/
│
├── 📄 weekend_break_finder_enhanced.py  ⭐ RUN THIS ONE!
├── 📄 price_tracker.py                  🎁 BONUS TOOL
│
├── 📖 README.md                         Quick start
├── 📖 SETUP_GUIDE.md                    Detailed setup
├── 📖 PROJECT_SUMMARY.md                Full overview
│
├── 📋 requirements.txt                  Dependencies
├── 📋 env.template                      API keys template
│
├── 📊 weekend_breaks.json               Sample output
└── 📊 weekend_breaks.csv                Sample output (Excel)
```

## Common Workflows

### Workflow 1: Quick Weekend Planning
```
1. Friday morning: Want to go somewhere next weekend
2. Run: python weekend_break_finder_enhanced.py
3. See results in 2 minutes
4. Pick cheapest/most interesting city
5. Book and go! ✈️
```

### Workflow 2: Price Tracking
```
Monday:     Run finder → Add to price tracker
Tuesday:    Run finder → Add to price tracker
Wednesday:  Run finder → Check trends
            See prices dropping? Book now!
```

### Workflow 3: Flexible Dates
```
1. Run for Nov 14-17 → Best: Krakow €149
2. Edit dates to Nov 21-24 → Best: Krakow €132
3. Edit dates to Nov 28-Dec 1 → Best: Krakow €178
4. Book Nov 21-24 (cheapest!) 💰
```

## Output Example

```
🏆 BEST WEEKEND BREAKS - RANKED BY TOTAL COST
═══════════════════════════════════════════════════════════════

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

## Time Comparison

```
MANUAL SEARCHING:                    WITH THIS TOOL:
┌────────────────────┐              ┌─────────────────┐
│                    │              │                 │
│ Google Flights     │              │ Run script      │
│ → 15 min per city  │              │ → 2 min total   │
│                    │              │                 │
│ Booking.com        │              │ Get ranked      │
│ → 15 min per city  │              │ → list of 20+   │
│                    │              │   cities        │
│ Check 10 cities    │              │                 │
│ → 5 HOURS! 😫      │              │ Done! ✅ 🎉     │
│                    │              │                 │
└────────────────────┘              └─────────────────┘
```

## Benefits At A Glance

```
✅ SAVES TIME:        5 hours → 2 minutes
✅ MORE OPTIONS:      You check 5 cities → Script checks 20+
✅ NEVER MISS DEALS:  Script finds hidden gems
✅ BUDGET FRIENDLY:   Filter by your budget
✅ TRACKABLE:         Monitor prices over time
✅ EXPORTABLE:        Share results with friends
✅ FREE:              Core features cost nothing!
```

## Ready?

```
┌─────────────────────────────────────────┐
│                                         │
│  You're all set! Just run:              │
│                                         │
│  $ python weekend_break_finder_         │
│    enhanced.py                          │
│                                         │
│  And find your next adventure! 🌍✈️     │
│                                         │
└─────────────────────────────────────────┘
```

---

**Questions?** Check README.md or SETUP_GUIDE.md

**Found a great deal?** That's what this is for! Enjoy your trip! 🎉
