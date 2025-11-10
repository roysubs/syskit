#!/usr/bin/env python3
"""
Price Tracker - Track weekend break prices over time
Run this script weekly to spot price trends and deals!
"""

import json
import os
from datetime import datetime
from typing import List, Dict
import csv


class PriceTracker:
    """Track weekend break prices over time"""
    
    def __init__(self, history_file: str = "price_history.json"):
        self.history_file = history_file
        self.history = self._load_history()
    
    def _load_history(self) -> List[Dict]:
        """Load price history from file"""
        if os.path.exists(self.history_file):
            with open(self.history_file, 'r') as f:
                return json.load(f)
        return []
    
    def _save_history(self):
        """Save price history to file"""
        with open(self.history_file, 'w') as f:
            json.dump(self.history, f, indent=2)
    
    def add_snapshot(self, results_file: str = "weekend_breaks.json"):
        """Add current results to price history"""
        if not os.path.exists(results_file):
            print(f"❌ Results file not found: {results_file}")
            return
        
        with open(results_file, 'r') as f:
            current_results = json.load(f)
        
        snapshot = {
            "timestamp": datetime.now().isoformat(),
            "date_checked": datetime.now().strftime("%Y-%m-%d"),
            "results": current_results
        }
        
        self.history.append(snapshot)
        self._save_history()
        
        print(f"✅ Added snapshot with {len(current_results)} destinations")
        print(f"📊 Total snapshots: {len(self.history)}")
    
    def compare_prices(self, city: str) -> None:
        """Compare prices for a specific city over time"""
        city_data = []
        
        for snapshot in self.history:
            for result in snapshot["results"]:
                if result["city"] == city:
                    city_data.append({
                        "date": snapshot["date_checked"],
                        "total_cost": result["total_cost"],
                        "transport_cost": result["transport_cost"],
                        "accommodation_cost": result["accommodation_cost"]
                    })
        
        if not city_data:
            print(f"❌ No historical data found for {city}")
            return
        
        print(f"\n📊 Price History for {city}")
        print("=" * 60)
        
        for entry in city_data:
            change = ""
            if len(city_data) > 1:
                first_price = city_data[0]["total_cost"]
                current_price = entry["total_cost"]
                diff = current_price - first_price
                pct = (diff / first_price) * 100
                
                if diff > 0:
                    change = f" 📈 +€{diff:.2f} (+{pct:.1f}%)"
                elif diff < 0:
                    change = f" 📉 €{diff:.2f} ({pct:.1f}%)"
                else:
                    change = " ➡️ No change"
            
            print(f"{entry['date']}: €{entry['total_cost']:.2f}{change}")
            print(f"  Transport: €{entry['transport_cost']:.2f} | Hotel: €{entry['accommodation_cost']:.2f}")
        
        # Summary
        if len(city_data) > 1:
            lowest = min(city_data, key=lambda x: x["total_cost"])
            highest = max(city_data, key=lambda x: x["total_cost"])
            
            print("\n💡 Summary:")
            print(f"   Best price: €{lowest['total_cost']:.2f} on {lowest['date']}")
            print(f"   Highest price: €{highest['total_cost']:.2f} on {highest['date']}")
            
            if city_data[-1]["total_cost"] == lowest["total_cost"]:
                print("   🎉 Current price is the BEST we've seen!")
            elif city_data[-1]["total_cost"] == highest["total_cost"]:
                print("   ⚠️  Current price is the HIGHEST we've seen!")
    
    def show_all_trends(self):
        """Show price trends for all cities"""
        if len(self.history) < 2:
            print("❌ Need at least 2 snapshots to show trends")
            return
        
        latest = self.history[-1]["results"]
        previous = self.history[-2]["results"]
        
        print("\n📊 Price Changes Since Last Check")
        print("=" * 70)
        
        for latest_city in latest:
            city_name = latest_city["city"]
            latest_price = latest_city["total_cost"]
            
            # Find matching city in previous snapshot
            prev_price = None
            for prev_city in previous:
                if prev_city["city"] == city_name:
                    prev_price = prev_city["total_cost"]
                    break
            
            if prev_price:
                diff = latest_price - prev_price
                pct = (diff / prev_price) * 100
                
                if abs(diff) < 1:
                    trend = "➡️"
                    color = ""
                elif diff > 0:
                    trend = "📈"
                    color = "UP"
                else:
                    trend = "📉"
                    color = "DOWN"
                
                print(f"{trend} {city_name:20} €{latest_price:.2f} ({color:4} €{abs(diff):.2f}, {pct:+.1f}%)")
    
    def export_trends_csv(self, filename: str = "price_trends.csv"):
        """Export price trends to CSV"""
        if not self.history:
            print("❌ No history to export")
            return
        
        # Collect all cities
        all_cities = set()
        for snapshot in self.history:
            for result in snapshot["results"]:
                all_cities.add(result["city"])
        
        with open(filename, 'w', newline='') as f:
            writer = csv.writer(f)
            
            # Header
            header = ["City"] + [s["date_checked"] for s in self.history]
            writer.writerow(header)
            
            # Data for each city
            for city in sorted(all_cities):
                row = [city]
                for snapshot in self.history:
                    price = None
                    for result in snapshot["results"]:
                        if result["city"] == city:
                            price = f"€{result['total_cost']:.2f}"
                            break
                    row.append(price or "-")
                writer.writerow(row)
        
        print(f"📊 Trends exported to {filename}")
    
    def find_best_deals(self, threshold_pct: float = 10.0):
        """Find cities with significant price drops"""
        if len(self.history) < 2:
            print("❌ Need at least 2 snapshots to find deals")
            return
        
        latest = self.history[-1]["results"]
        previous = self.history[-2]["results"]
        
        deals = []
        
        for latest_city in latest:
            city_name = latest_city["city"]
            latest_price = latest_city["total_cost"]
            
            for prev_city in previous:
                if prev_city["city"] == city_name:
                    prev_price = prev_city["total_cost"]
                    diff = latest_price - prev_price
                    pct = (diff / prev_price) * 100
                    
                    if pct <= -threshold_pct:  # Price dropped by at least threshold
                        deals.append({
                            "city": city_name,
                            "previous_price": prev_price,
                            "current_price": latest_price,
                            "savings": -diff,
                            "percentage": -pct
                        })
                    break
        
        if deals:
            deals.sort(key=lambda x: x["percentage"], reverse=True)
            
            print(f"\n🎉 DEALS ALERT! Price drops > {threshold_pct}%")
            print("=" * 70)
            
            for deal in deals:
                print(f"📉 {deal['city']}")
                print(f"   Was: €{deal['previous_price']:.2f} → Now: €{deal['current_price']:.2f}")
                print(f"   💰 Save €{deal['savings']:.2f} ({deal['percentage']:.1f}% off)")
                print()
        else:
            print(f"\n😐 No significant deals found (>{threshold_pct}% drop)")


def main():
    """Main function"""
    print("📈 Weekend Break Price Tracker")
    print("=" * 60)
    
    tracker = PriceTracker()
    
    # Check if we have results to add
    if os.path.exists("weekend_breaks.json"):
        print("\nFound latest results. Options:")
        print("1. Add to tracking history")
        print("2. View price trends")
        print("3. Find best deals")
        print("4. Compare specific city")
        print("5. Export trends to CSV")
        
        choice = input("\nEnter choice (1-5): ").strip()
        
        if choice == "1":
            tracker.add_snapshot()
        elif choice == "2":
            tracker.show_all_trends()
        elif choice == "3":
            threshold = input("Enter minimum savings % (default 10): ").strip()
            threshold = float(threshold) if threshold else 10.0
            tracker.find_best_deals(threshold)
        elif choice == "4":
            city = input("Enter city name: ").strip()
            tracker.compare_prices(city)
        elif choice == "5":
            tracker.export_trends_csv()
        else:
            print("Invalid choice")
    else:
        print("\n⚠️  No results found. Run weekend_break_finder_enhanced.py first!")
        print("   Then come back here to track prices over time.")
    
    print("\n💡 TIP: Run the finder weekly and add snapshots here to track deals!")


if __name__ == "__main__":
    main()
