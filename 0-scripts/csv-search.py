#!/usr/bin/env python3
# Author: Roy Wiseman 2025-01
import csv
import sys
import re

def print_usage():
    print("""
A generic CSV search tool.
Usage: {script_name} <csv_file> [field=search_term ...]

Args:
    csv_file (str): The path to the CSV file.
    **filters: Keyword arguments in the form "field=search_term".
               Note that numerical fields support "int+/-" so "80", or "80+", or "80-".
               where 80+ would find values of 80 and above, and 80- values of 80 or below.
""".replace("{script_name}", sys.argv[0]))

def generic_csv_search(csv_file, **filters):
    try:
        with open(csv_file, 'r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            data = list(reader)

            if not filters:
                # If no filters provided, print field names and row count
                if data:
                    print(f"Available fields: {', '.join(data[0].keys())}")
                print(f"Total rows: {len(data)}")
                print_usage()
                return

            results = data[:]  # Start with all rows and filter down

            for field, search_term in filters.items():
                if field not in data[0].keys():
                    print(f"Warning: Field '{field}' not found. Skipping.")
                    continue

                filtered_results = []
                for row in results:
                    value = row.get(field)
                    if value is None:
                        continue  # Skip rows where the field is missing

                    if value.isdigit() and (search_term.endswith('+') or search_term.endswith('-')):
                        # Numerical field with range operator
                        try:
                            num_value = int(value)
                            target_num = int(search_term[:-1])
                            if search_term.endswith('+') and num_value >= target_num:
                                filtered_results.append(row)
                            elif search_term.endswith('-') and num_value <= target_num:
                                filtered_results.append(row)
                            elif search_term == str(num_value):
                                filtered_results.append(row)
                        except ValueError:
                            print(f"Warning: Invalid numerical filter '{search_term}' for field '{field}'.")
                            continue
                    elif "*" in search_term:
                        # Wildcard search
                        pattern = re.escape(search_term).replace("\\*", ".*")
                        if re.search(pattern, str(value), re.IGNORECASE):
                            filtered_results.append(row)
                    elif search_term.lower() in str(value).lower():
                        # Basic substring search
                        filtered_results.append(row)
                results = filtered_results

            if results:
                # Print header
                header = results[0].keys()
                print(",".join(f'"{field}"' for field in header))

                # Print rows
                for row in results:
                    print(",".join(f'"{row[field]}"' for field in header))
            else:
                print("No matching records found.")

    except FileNotFoundError:
        print("Error: File not found.")
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(1)

    csv_file = sys.argv[1]
    filters = {}

    for arg in sys.argv[2:]:
        if "=" in arg:
            field, search_term = arg.split("=", 1)
            filters[field] = search_term
        else:
            print(f"Warning: Invalid argument '{arg}'. Expected 'field=search_term'.")

    generic_csv_search(csv_file, **filters)
