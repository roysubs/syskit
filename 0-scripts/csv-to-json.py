#!/usr/bin/env python3
# Author: Roy Wiseman 2025-05

import csv
import json
import sys

def csv_to_json(csv_file):
    """
    Reads a CSV file and converts it to JSON format.

    Args:
        csv_file (str): The path to the CSV file.
    """

    try:
        with open(csv_file, 'r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            data = list(reader)

        print(json.dumps(data, indent=4))  # Output JSON with indentation

    except FileNotFoundError:
        print("Error: File not found.")
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        script_name = sys.argv[0]
        print(f"Usage: {script_name} <csv_file>")
        sys.exit(1)

    csv_file = sys.argv[1]
    csv_to_json(csv_file)
