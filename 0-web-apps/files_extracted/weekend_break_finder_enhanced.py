#!/usr/bin/env python3
"""
Weekend Break Finder - Enhanced Version
Now with DEMO MODE for testing without API keys!
"""

import requests
import json
from datetime import datetime, timedelta
from typing import List, Dict, Optional
import os
from dataclasses import dataclass, asdict
import time
import random


@dataclass
class FlightOption:
    """Represents a flight option"""
    origin: str
    destination: str
    outbound_date: str
    return_date: str
    price: float
    currency: str
    carrier: str
    departure_time: str
    is_direct: bool
    booking_link: str


@dataclass
class TrainOption:
    """Represents a train option"""
    origin: str
    destination: str
    outbound_date: str
    return_date: str
    price: float
    currency: str
    duration_hours: float
    booking_link: str


@dataclass
class AccommodationOption:
    """Represents accommodation"""
    city: str
    name: str
    price_per_night: float
    total_price: float
    currency: str
    rating: float
    distance_from_center_km: float
    booking_link: str


@dataclass
class CityBreak:
    """Complete city break package"""
    city: str
    country: str
    transport_type: str
    transport_cost: float
    accommodation_cost: float
    total_cost: float
    currency: str
    flight_details: Optional[FlightOption] = None
    train_details: Optional[TrainOption] = None
    accommodation_details: Optional[AccommodationOption] = None
    
    def to_dict(self):
        return asdict(self)


class WeekendBreakFinder:
    """Main class to search and rank weekend breaks"""
    
    EUROPEAN_CITIES = [
        {"name": "Barcelona", "country": "Spain", "code": "BCN"},
        {"name": "Paris", "country": "France", "code": "CDG"},
        {"name": "Rome", "country": "Italy", "code": "FCO"},
        {"name": "Berlin", "country": "Germany", "code": "BER"},
        {"name": "Prague", "country": "Czech Republic", "code": "PRG"},
        {"name": "Budapest", "country": "Hungary", "code": "BUD"},
        {"name": "Vienna", "country": "Austria", "code": "VIE"},
        {"name": "Lisbon", "country": "Portugal", "code": "LIS"},
        {"name": "Copenhagen", "country": "Denmark", "code": "CPH"},
        {"name": "Dublin", "country": "Ireland", "code": "DUB"},
        {"name": "Brussels", "country": "Belgium", "code": "BRU"},
        {"name": "Milan", "country": "Italy", "code": "MXP"},
        {"name": "Munich", "country": "Germany", "code": "MUC"},
        {"name": "Edinburgh", "country": "Scotland", "code": "EDI"},
        {"name": "Stockholm", "country": "Sweden", "code": "ARN"},
        {"name": "Porto", "country": "Portugal", "code": "OPO"},
        {"name": "Krakow", "country": "Poland", "code": "KRK"},
        {"name": "Valencia", "country": "Spain", "code": "VLC"},
        {"name": "Athens", "country": "Greece", "code": "ATH"},
        {"name": "Seville", "country": "Spain", "code": "SVQ"},
    ]
    
    def __init__(self, origin_city: str = "Amsterdam", demo_mode: bool = False):
        self.origin_city = origin_city
        self.origin_code = "AMS"
        self.demo_mode = demo_mode
        
        # API keys
        self.amadeus_api_key = os.getenv("AMADEUS_API_KEY")
        self.amadeus_api_secret = os.getenv("AMADEUS_API_SECRET")
        self.booking_api_key = os.getenv("BOOKING_API_KEY")
        
        self.amadeus_token = None
        
        # Demo mode flight prices (realistic estimates)
        self.demo_flight_prices = {
            "BCN": 85, "CDG": 75, "FCO": 95, "BER": 70, "PRG": 65,
            "BUD": 60, "VIE": 80, "LIS": 90, "CPH": 85, "DUB": 70,
            "BRU": 50, "MXP": 75, "MUC": 80, "EDI": 85, "ARN": 90,
            "OPO": 85, "KRK": 55, "VLC": 80, "ATH": 110, "SVQ": 90
        }
        
        self.airlines = ["KL", "FR", "U2", "VY", "W6", "TP", "IB"]  # Airlines
        
    def get_amadeus_token(self) -> Optional[str]:
        """Get OAuth token for Amadeus API"""
        if self.demo_mode:
            return "DEMO_MODE"
            
        if not self.amadeus_api_key or not self.amadeus_api_secret:
            return None
            
        try:
            url = "https://test.api.amadeus.com/v1/security/oauth2/token"
            headers = {"Content-Type": "application/x-www-form-urlencoded"}
            data = {
                "grant_type": "client_credentials",
                "client_id": self.amadeus_api_key,
                "client_secret": self.amadeus_api_secret
            }
            
            response = requests.post(url, headers=headers, data=data)
            if response.status_code == 200:
                self.amadeus_token = response.json()["access_token"]
                return self.amadeus_token
            else:
                return None
        except Exception as e:
            return None
    
    def generate_demo_flight(self, destination_code: str, destination_name: str,
                           outbound_date: str, return_date: str) -> Optional[FlightOption]:
        """Generate realistic demo flight data"""
        base_price = self.demo_flight_prices.get(destination_code, 80)
        
        # Add some variation (+/- 20%)
        price = base_price * random.uniform(0.8, 1.2)
        
        # Random morning/afternoon departure
        departure_times = ["08:30:00", "10:15:00", "11:45:00", "13:20:00", "15:10:00", "16:40:00"]
        departure_time = f"{outbound_date}T{random.choice(departure_times)}"
        
        airline = random.choice(self.airlines)
        
        return FlightOption(
            origin=self.origin_code,
            destination=destination_code,
            outbound_date=outbound_date,
            return_date=return_date,
            price=round(price, 2),
            currency="EUR",
            carrier=airline,
            departure_time=departure_time,
            is_direct=True,
            booking_link=f"https://www.google.com/flights?q=flights+from+{self.origin_code}+to+{destination_code}"
        )
    
    def search_flights(self, destination_code: str, destination_name: str,
                      outbound_date: str, return_date: str) -> List[FlightOption]:
        """Search for flights using Amadeus API or demo data"""
        
        # Use demo mode if enabled or no API credentials
        if self.demo_mode or not self.amadeus_api_key:
            flight = self.generate_demo_flight(destination_code, destination_name, 
                                              outbound_date, return_date)
            return [flight] if flight else []
        
        # Real API call
        if not self.amadeus_token:
            self.amadeus_token = self.get_amadeus_token()
            if not self.amadeus_token:
                return []
        
        try:
            url = "https://test.api.amadeus.com/v2/shopping/flight-offers"
            headers = {"Authorization": f"Bearer {self.amadeus_token}"}
            
            params = {
                "originLocationCode": self.origin_code,
                "destinationLocationCode": destination_code,
                "departureDate": outbound_date,
                "returnDate": return_date,
                "adults": 1,
                "nonStop": "true",
                "currencyCode": "EUR",
                "max": 5
            }
            
            response = requests.get(url, headers=headers, params=params, timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                flights = []
                
                if "data" in data:
                    for offer in data["data"]:
                        outbound_segment = offer["itineraries"][0]["segments"][0]
                        departure_time = outbound_segment["departure"]["at"]
                        hour = int(departure_time.split("T")[1].split(":")[0])
                        
                        if hour >= 19:
                            continue
                        
                        flight = FlightOption(
                            origin=self.origin_code,
                            destination=destination_code,
                            outbound_date=outbound_date,
                            return_date=return_date,
                            price=float(offer["price"]["total"]),
                            currency=offer["price"]["currency"],
                            carrier=outbound_segment["carrierCode"],
                            departure_time=departure_time,
                            is_direct=len(offer["itineraries"][0]["segments"]) == 1,
                            booking_link=f"https://www.google.com/flights?q=flights+from+{self.origin_code}+to+{destination_code}"
                        )
                        flights.append(flight)
                
                return flights
            else:
                return []
                
        except Exception as e:
            return []
    
    def estimate_train_option(self, destination_city: str, 
                             destination_country: str) -> Optional[TrainOption]:
        """Estimate train options for cities within 5 hours"""
        train_reachable = {
            "Brussels": {"hours": 2, "price": 40},
            "Paris": {"hours": 3.5, "price": 70},
            "Cologne": {"hours": 2.5, "price": 35},
            "Frankfurt": {"hours": 4, "price": 60},
        }
        
        if destination_city in train_reachable:
            info = train_reachable[destination_city]
            if info["hours"] <= 5:
                return TrainOption(
                    origin=self.origin_city,
                    destination=destination_city,
                    outbound_date="",
                    return_date="",
                    price=info["price"] * 2,
                    currency="EUR",
                    duration_hours=info["hours"],
                    booking_link=f"https://www.thetrainline.com"
                )
        
        return None
    
    def search_accommodation(self, city_name: str, check_in: str, 
                           check_out: str) -> List[AccommodationOption]:
        """Search for accommodation"""
        city_prices = {
            "Barcelona": 80, "Paris": 90, "Rome": 70, "Berlin": 65,
            "Prague": 50, "Budapest": 45, "Vienna": 75, "Lisbon": 60,
            "Copenhagen": 95, "Dublin": 85, "Brussels": 70, "Milan": 75,
            "Munich": 80, "Edinburgh": 75, "Stockholm": 90, "Porto": 55,
            "Krakow": 40, "Valencia": 60, "Athens": 65, "Seville": 65
        }
        
        check_in_date = datetime.strptime(check_in, "%Y-%m-%d")
        check_out_date = datetime.strptime(check_out, "%Y-%m-%d")
        nights = (check_out_date - check_in_date).days
        
        price_per_night = city_prices.get(city_name, 70)
        
        options = []
        hotel_names = [
            f"{city_name} Central Hotel",
            f"Budget Stay {city_name}",
            f"Boutique {city_name}"
        ]
        
        for i in range(3):
            variation = price_per_night * (0.8 + i * 0.2)
            
            accommodation = AccommodationOption(
                city=city_name,
                name=hotel_names[i],
                price_per_night=variation,
                total_price=variation * nights,
                currency="EUR",
                rating=4.0 + (i * 0.3),
                distance_from_center_km=0.5 + (i * 0.5),
                booking_link=f"https://www.booking.com/city/{city_name.lower()}.html"
            )
            options.append(accommodation)
        
        return options
    
    def find_best_breaks(self, outbound_date: str, return_date: str, 
                        max_results: int = 10, min_budget: float = 0,
                        max_budget: float = float('inf')) -> List[CityBreak]:
        """
        Main method to search all cities and rank by total cost.
        
        Args:
            outbound_date: Departure date (YYYY-MM-DD)
            return_date: Return date (YYYY-MM-DD)
            max_results: Number of top results to return
            min_budget: Minimum total budget (optional)
            max_budget: Maximum total budget (optional)
        """
        mode_text = "DEMO MODE (estimated prices)" if self.demo_mode or not self.amadeus_api_key else "LIVE MODE"
        print(f"\n🔍 Searching for weekend breaks from {self.origin_city}... [{mode_text}]")
        print(f"📅 Dates: {outbound_date} to {return_date}")
        if max_budget < float('inf'):
            print(f"💰 Budget: €{min_budget:.0f} - €{max_budget:.0f}")
        print()
        
        all_breaks = []
        
        for city in self.EUROPEAN_CITIES:
            print(f"Checking {city['name']}, {city['country']}...", end=" ")
            
            flights = self.search_flights(city["code"], city["name"], outbound_date, return_date)
            train = self.estimate_train_option(city["name"], city["country"])
            accommodations = self.search_accommodation(city["name"], outbound_date, return_date)
            
            if not accommodations:
                print("❌ No accommodation")
                continue
            
            best_accommodation = min(accommodations, key=lambda x: x.total_price)
            
            # Flight option
            if flights:
                best_flight = min(flights, key=lambda x: x.price)
                total = best_flight.price + best_accommodation.total_price
                
                if min_budget <= total <= max_budget:
                    city_break = CityBreak(
                        city=city["name"],
                        country=city["country"],
                        transport_type="flight",
                        transport_cost=best_flight.price,
                        accommodation_cost=best_accommodation.total_price,
                        total_cost=total,
                        currency="EUR",
                        flight_details=best_flight,
                        accommodation_details=best_accommodation
                    )
                    all_breaks.append(city_break)
                print(f"✓ €{total:.0f}")
            
            # Train option
            if train:
                total = train.price + best_accommodation.total_price
                
                if min_budget <= total <= max_budget:
                    city_break = CityBreak(
                        city=city["name"],
                        country=city["country"],
                        transport_type="train",
                        transport_cost=train.price,
                        accommodation_cost=best_accommodation.total_price,
                        total_cost=total,
                        currency="EUR",
                        train_details=train,
                        accommodation_details=best_accommodation
                    )
                    all_breaks.append(city_break)
            
            if not flights and not train:
                print("❌ No transport")
            
            time.sleep(0.1)  # Small delay to be nice
        
        all_breaks.sort(key=lambda x: x.total_cost)
        return all_breaks[:max_results]
    
    def display_results(self, breaks: List[CityBreak]):
        """Display results in a nice formatted way"""
        if not breaks:
            print("\n❌ No results found matching your criteria.")
            return
            
        print("\n" + "="*80)
        print("🏆 BEST WEEKEND BREAKS - RANKED BY TOTAL COST")
        print("="*80 + "\n")
        
        for i, break_option in enumerate(breaks, 1):
            print(f"{i}. {break_option.city}, {break_option.country}")
            print(f"   Transport: {break_option.transport_type.upper()} - €{break_option.transport_cost:.2f}")
            print(f"   Accommodation: €{break_option.accommodation_cost:.2f} ({break_option.accommodation_details.price_per_night:.2f}/night)")
            print(f"   💰 TOTAL: €{break_option.total_cost:.2f}")
            
            if break_option.flight_details:
                time_str = break_option.flight_details.departure_time.split("T")[1][:5]
                print(f"   ✈️  {break_option.flight_details.carrier} - Departs {time_str}")
            elif break_option.train_details:
                print(f"   🚂 {break_option.train_details.duration_hours:.1f}h journey")
            
            print(f"   🏨 {break_option.accommodation_details.name}")
            print(f"      ⭐ {break_option.accommodation_details.rating:.1f} rating")
            print(f"      📍 {break_option.accommodation_details.distance_from_center_km:.1f}km from center")
            print()
    
    def save_results(self, breaks: List[CityBreak], filename: str = "weekend_breaks.json"):
        """Save results to JSON file"""
        data = [break_option.to_dict() for break_option in breaks]
        
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2, default=str)
        
        print(f"💾 Results saved to {filename}")
    
    def export_to_csv(self, breaks: List[CityBreak], filename: str = "weekend_breaks.csv"):
        """Export results to CSV for easy viewing in Excel"""
        import csv
        
        with open(filename, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([
                "Rank", "City", "Country", "Transport Type", "Transport Cost",
                "Accommodation Cost", "Total Cost", "Hotel Name", "Rating",
                "Distance from Center (km)"
            ])
            
            for i, break_option in enumerate(breaks, 1):
                writer.writerow([
                    i,
                    break_option.city,
                    break_option.country,
                    break_option.transport_type,
                    f"€{break_option.transport_cost:.2f}",
                    f"€{break_option.accommodation_cost:.2f}",
                    f"€{break_option.total_cost:.2f}",
                    break_option.accommodation_details.name,
                    break_option.accommodation_details.rating,
                    break_option.accommodation_details.distance_from_center_km
                ])
        
        print(f"📊 Results exported to {filename}")


def main():
    """Main function"""
    
    # Configuration
    ORIGIN_CITY = "Amsterdam"
    OUTBOUND_DATE = "2025-11-14"  # Friday
    RETURN_DATE = "2025-11-17"    # Monday
    
    # Budget constraints (optional)
    MIN_BUDGET = 0
    MAX_BUDGET = 400  # Set to float('inf') for no limit
    
    # Enable demo mode if no API keys
    DEMO_MODE = True  # Set to False when you have API keys
    
    print("🌍 Weekend Break Finder - Enhanced Edition")
    print("="*80)
    
    finder = WeekendBreakFinder(origin_city=ORIGIN_CITY, demo_mode=DEMO_MODE)
    
    results = finder.find_best_breaks(
        OUTBOUND_DATE, 
        RETURN_DATE, 
        max_results=10,
        min_budget=MIN_BUDGET,
        max_budget=MAX_BUDGET
    )
    
    finder.display_results(results)
    finder.save_results(results)
    finder.export_to_csv(results)
    
    print("\n✅ Search complete!")
    
    if DEMO_MODE:
        print("\n💡 TIP: You're in DEMO MODE with estimated prices.")
        print("   For real prices, set up Amadeus API keys (it's free!)")
        print("   See SETUP_GUIDE.md for instructions.")


if __name__ == "__main__":
    main()
