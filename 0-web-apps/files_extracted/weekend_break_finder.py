#!/usr/bin/env python3
"""
Weekend Break Finder
Searches for the best-priced weekend breaks across European cities.
Compares flights, trains, and accommodation to rank destinations by total cost.
"""

import requests
import json
from datetime import datetime, timedelta
from typing import List, Dict, Optional
import os
from dataclasses import dataclass, asdict
import time


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
    transport_type: str  # 'flight' or 'train'
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
    
    # European cities to search (IATA codes and city info)
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
    ]
    
    def __init__(self, origin_city: str = "Amsterdam"):
        self.origin_city = origin_city
        self.origin_code = "AMS"  # Amsterdam Schiphol
        
        # API keys - to be set by user
        self.amadeus_api_key = os.getenv("AMADEUS_API_KEY")
        self.amadeus_api_secret = os.getenv("AMADEUS_API_SECRET")
        self.booking_api_key = os.getenv("BOOKING_API_KEY")
        
        # Amadeus token
        self.amadeus_token = None
        
    def get_amadeus_token(self) -> Optional[str]:
        """Get OAuth token for Amadeus API"""
        if not self.amadeus_api_key or not self.amadeus_api_secret:
            print("⚠️  Amadeus API credentials not found. Set AMADEUS_API_KEY and AMADEUS_API_SECRET environment variables.")
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
                print(f"❌ Failed to get Amadeus token: {response.status_code}")
                return None
        except Exception as e:
            print(f"❌ Error getting Amadeus token: {e}")
            return None
    
    def search_flights(self, destination_code: str, outbound_date: str, 
                      return_date: str) -> List[FlightOption]:
        """Search for flights using Amadeus API"""
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
                "nonStop": "true",  # Direct flights only
                "currencyCode": "EUR",
                "max": 5
            }
            
            response = requests.get(url, headers=headers, params=params, timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                flights = []
                
                if "data" in data:
                    for offer in data["data"]:
                        # Check departure time (no flights after 7pm)
                        outbound_segment = offer["itineraries"][0]["segments"][0]
                        departure_time = outbound_segment["departure"]["at"]
                        hour = int(departure_time.split("T")[1].split(":")[0])
                        
                        if hour >= 19:  # 7pm or later
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
                print(f"⚠️  Flight search failed for {destination_code}: {response.status_code}")
                return []
                
        except Exception as e:
            print(f"⚠️  Error searching flights to {destination_code}: {e}")
            return []
    
    def estimate_train_option(self, destination_city: str, destination_country: str) -> Optional[TrainOption]:
        """
        Estimate train options for cities within 5 hours of Amsterdam.
        This is a simplified version - in production you'd use Rail Europe or Trainline API.
        """
        # Approximate train journey times from Amsterdam (in hours)
        train_reachable = {
            "Brussels": {"hours": 2, "price": 40},
            "Paris": {"hours": 3.5, "price": 70},
            "Berlin": {"hours": 6.5, "price": 80},  # Too long
            "Cologne": {"hours": 2.5, "price": 35},
            "Frankfurt": {"hours": 4, "price": 60},
        }
        
        if destination_city in train_reachable:
            info = train_reachable[destination_city]
            if info["hours"] <= 5:  # Only if 5 hours or less
                return TrainOption(
                    origin=self.origin_city,
                    destination=destination_city,
                    outbound_date="",  # Would be filled by API
                    return_date="",
                    price=info["price"] * 2,  # Return ticket
                    currency="EUR",
                    duration_hours=info["hours"],
                    booking_link=f"https://www.thetrainline.com"
                )
        
        return None
    
    def search_accommodation(self, city_name: str, check_in: str, 
                           check_out: str) -> List[AccommodationOption]:
        """
        Search for accommodation using Booking.com-style API.
        This is a placeholder - you'd need proper API access or web scraping.
        """
        # For demo purposes, return estimated prices
        # In production, use Booking.com API or scraping with proper rate limiting
        
        # Estimated average prices for city center accommodation per night
        city_prices = {
            "Barcelona": 80, "Paris": 90, "Rome": 70, "Berlin": 65,
            "Prague": 50, "Budapest": 45, "Vienna": 75, "Lisbon": 60,
            "Copenhagen": 95, "Dublin": 85, "Brussels": 70, "Milan": 75,
            "Munich": 80, "Edinburgh": 75, "Stockholm": 90, "Porto": 55,
            "Krakow": 40, "Valencia": 60
        }
        
        check_in_date = datetime.strptime(check_in, "%Y-%m-%d")
        check_out_date = datetime.strptime(check_out, "%Y-%m-%d")
        nights = (check_out_date - check_in_date).days
        
        price_per_night = city_prices.get(city_name, 70)  # Default 70 EUR
        
        # Add some variation
        options = []
        for i in range(3):
            variation = price_per_night * (0.8 + i * 0.2)  # 80%, 100%, 120% of base
            
            accommodation = AccommodationOption(
                city=city_name,
                name=f"Central Hotel Option {i+1}",
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
                        max_results: int = 10) -> List[CityBreak]:
        """
        Main method to search all cities and rank by total cost.
        
        Args:
            outbound_date: Departure date (YYYY-MM-DD)
            return_date: Return date (YYYY-MM-DD)
            max_results: Number of top results to return
        """
        print(f"\n🔍 Searching for weekend breaks from {self.origin_city}...")
        print(f"📅 Dates: {outbound_date} to {return_date}\n")
        
        all_breaks = []
        
        for city in self.EUROPEAN_CITIES:
            print(f"Checking {city['name']}, {city['country']}...", end=" ")
            
            # Search flights
            flights = self.search_flights(city["code"], outbound_date, return_date)
            
            # Check train option
            train = self.estimate_train_option(city["name"], city["country"])
            
            # Search accommodation
            accommodations = self.search_accommodation(city["name"], outbound_date, return_date)
            
            if not accommodations:
                print("❌ No accommodation found")
                continue
            
            # Create city breaks for each transport option
            best_accommodation = min(accommodations, key=lambda x: x.total_price)
            
            # Flight option
            if flights:
                best_flight = min(flights, key=lambda x: x.price)
                city_break = CityBreak(
                    city=city["name"],
                    country=city["country"],
                    transport_type="flight",
                    transport_cost=best_flight.price,
                    accommodation_cost=best_accommodation.total_price,
                    total_cost=best_flight.price + best_accommodation.total_price,
                    currency="EUR",
                    flight_details=best_flight,
                    accommodation_details=best_accommodation
                )
                all_breaks.append(city_break)
                print(f"✓ Flight: €{best_flight.price:.0f}")
            
            # Train option
            if train:
                city_break = CityBreak(
                    city=city["name"],
                    country=city["country"],
                    transport_type="train",
                    transport_cost=train.price,
                    accommodation_cost=best_accommodation.total_price,
                    total_cost=train.price + best_accommodation.total_price,
                    currency="EUR",
                    train_details=train,
                    accommodation_details=best_accommodation
                )
                all_breaks.append(city_break)
                print(f"  Train: €{train.price:.0f}")
            
            if not flights and not train:
                print("❌ No transport options found")
            
            # Be nice to APIs
            time.sleep(0.5)
        
        # Sort by total cost
        all_breaks.sort(key=lambda x: x.total_cost)
        
        return all_breaks[:max_results]
    
    def display_results(self, breaks: List[CityBreak]):
        """Display results in a nice formatted way"""
        print("\n" + "="*80)
        print("🏆 BEST WEEKEND BREAKS - RANKED BY TOTAL COST")
        print("="*80 + "\n")
        
        for i, break_option in enumerate(breaks, 1):
            print(f"{i}. {break_option.city}, {break_option.country}")
            print(f"   Transport: {break_option.transport_type.upper()} - €{break_option.transport_cost:.2f}")
            print(f"   Accommodation: €{break_option.accommodation_cost:.2f}")
            print(f"   💰 TOTAL: €{break_option.total_cost:.2f}")
            
            if break_option.flight_details:
                print(f"   ✈️  {break_option.flight_details.carrier} - Departs {break_option.flight_details.departure_time}")
            elif break_option.train_details:
                print(f"   🚂 {break_option.train_details.duration_hours:.1f} hours journey")
            
            print(f"   🏨 {break_option.accommodation_details.name}")
            print(f"      Rating: {break_option.accommodation_details.rating:.1f} ⭐")
            print(f"      Location: {break_option.accommodation_details.distance_from_center_km:.1f}km from center")
            print()
    
    def save_results(self, breaks: List[CityBreak], filename: str = "weekend_breaks.json"):
        """Save results to JSON file"""
        data = [break_option.to_dict() for break_option in breaks]
        
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2, default=str)
        
        print(f"💾 Results saved to {filename}")


def main():
    """Main function to run the weekend break finder"""
    
    # Configuration
    ORIGIN_CITY = "Amsterdam"
    OUTBOUND_DATE = "2025-11-14"  # Friday
    RETURN_DATE = "2025-11-17"    # Monday
    
    print("🌍 Weekend Break Finder")
    print("="*80)
    
    # Initialize finder
    finder = WeekendBreakFinder(origin_city=ORIGIN_CITY)
    
    # Find best breaks
    results = finder.find_best_breaks(OUTBOUND_DATE, RETURN_DATE, max_results=10)
    
    # Display results
    finder.display_results(results)
    
    # Save to file
    finder.save_results(results)
    
    print("\n✅ Search complete!")
    print("\nℹ️  Note: Some data is estimated. For production use:")
    print("   - Set up Amadeus API keys for real flight data")
    print("   - Integrate Booking.com or Airbnb API for accommodation")
    print("   - Add Trainline/Rail Europe API for accurate train prices")


if __name__ == "__main__":
    main()
