#!/usr/bin/env python3
# Author: Roy Wiseman 2025-01

import docker
import psutil
import time
import csv
import sys
import os
import statistics
from datetime import datetime
import argparse
import re # Import regex for parsing duration


# --- Configuration ---
MONITOR_INTERVAL = 1 # seconds
OUTPUT_DIR = "./monitoring_data" # Directory to save CSV data

# --- Helper to format bytes nicely ---
def format_bytes(byte_count):
    if byte_count is None:
        return "N/A"
    byte_count = float(byte_count)
    # Handle potential negative delta if system time jumps back, treat as 0 rate
    if byte_count < 0:
        return "0 B"
    for unit in ['B', 'KB', 'MB', 'GB', 'TB', 'PB']: # Added PB just in case!
        if abs(byte_count) < 1024.0:
            # Decide on precision based on scale? Keep it simple for now.
            # Limit precision for small values to avoid .00 B
            if abs(byte_count) < 10:
                return f"{byte_count:.0f} {unit}"
            return f"{byte_count:.2f} {unit}"
        byte_count /= 1024.0
    return f"{byte_count:.2f} EB" # Exabytes? Hopefully not needed!


# --- Helper to calculate container CPU percentage ---
# Based on Docker's calculation using cpu_stats and precpu_stats
def calculate_container_cpu_percent(stats, prev_stats):
    cpu_percent = 0.0
    # Need both current and previous stats to calculate delta
    if prev_stats and 'cpu_stats' in stats and 'precpu_stats' in prev_stats:
        # Ensure required keys exist in both current and previous stats
        if ('cpu_usage' in stats['cpu_stats'] and 'total_usage' in stats['cpu_stats']['cpu_usage'] and
            'cpu_usage' in prev_stats['cpu_stats'] and 'total_usage' in prev_stats['cpu_stats']['cpu_usage'] and
            'system_cpu_usage' in stats['cpu_stats'] and 'system_cpu_usage' in prev_stats['precpu_stats']):

            cpu_delta = stats['cpu_stats']['cpu_usage']['total_usage'] - prev_stats['cpu_stats']['cpu_usage']['total_usage']
            system_delta = stats['cpu_stats']['system_cpu_usage'] - prev_stats['precpu_stats'].get('system_cpu_usage', 0) # Use .get with default 0 for robustness

            # Determine the number of online CPUs. Prefer 'online_cpus' if available,
            # otherwise fall back to the length of 'percpu_usage' list if available,
            # otherwise use the host's logical CPU count as a reasonable default.
            online_cpus = stats['cpu_stats'].get('online_cpus')
            if online_cpus is None or online_cpus == 0:
                if 'cpu_usage' in stats['cpu_stats'] and 'percpu_usage' in stats['cpu_stats']['cpu_usage']:
                     online_cpus = len(stats['cpu_stats']['cpu_usage']['percpu_usage'])

            # Final fallback to host CPU count if container data is incomplete or ambiguous
            if online_cpus is None or online_cpus == 0:
                 online_cpus = psutil.cpu_count(logical=True)
                 if online_cpus is None or online_cpus == 0: # Should not happen on Linux typically
                     online_cpus = 1 # Absolute minimum default


            if system_delta > 0 and cpu_delta > 0:
                cpu_percent = (cpu_delta / system_delta) * online_cpus * 100.0

    return cpu_percent

# --- Function to parse duration string (e.g., "60s", "5m") ---
def parse_duration(duration_str):
    match = re.match(r'^(\d+)([sm])$', duration_str.lower())
    if not match:
        raise argparse.ArgumentTypeError(f"Invalid duration format: '{duration_str}'. Use digits followed by 's' or 'm' (e.g., 60s, 5m).")
    value = int(match.group(1))
    unit = match.group(2)
    if unit == 'm':
        value *= 60 # Convert minutes to seconds
    if value <= 0:
         raise argparse.ArgumentTypeError(f"Duration must be positive: {duration_str}.")
    return value

# --- Function to collect a single snapshot of data ---
def collect_snapshot(client):
    data_points = []
    current_time = time.time()

    # --- Get Host Stats ---
    try:
        # cpu_percent(interval=None) gives the instantaneous usage since last call,
        # or average since module import if first call. It's okay for a snapshot.
        host_cpu_percent = psutil.cpu_percent(interval=None)
        host_mem = psutil.virtual_memory()
        host_mem_usage_bytes = host_mem.used

        # For a single snapshot, we report cumulative IO bytes, not rate
        current_host_io = psutil.disk_io_counters()
        host_io_read_cumulative = current_host_io.read_bytes if current_host_io else 0
        host_io_write_cumulative = current_host_io.write_bytes if current_host_io else 0


        host_data = {
            'timestamp': current_time,
            'source': 'host',
            'cpu_percent': host_cpu_percent, # Snapshot CPU percentage
            'mem_usage_bytes': host_mem_usage_bytes,
            'io_read_bytes': host_io_read_cumulative, # Cumulative for snapshot
            'io_write_bytes': host_io_write_cumulative # Cumulative for snapshot
        }
        data_points.append(host_data)

    except Exception as e:
        print(f"Error getting host snapshot stats: {e}", file=sys.stderr)

    # --- Get Container Stats ---
    running_containers = []
    try:
        # Only list running containers as requested
        running_containers = client.containers.list(filters={"status": "running"})
    except Exception as e:
        print(f"Error listing containers: {e}", file=sys.stderr)

    for container in running_containers:
        try:
            stats = container.stats(stream=False) # Get a snapshot
            container_name = container.name

            # For a single snapshot, we report the current memory usage and cumulative IO
            # CPU percentage calculation from delta over time is not applicable for a single point.
            # We will report the instantaneous CPU % provided by psutil for the host,
            # but for containers, docker stats snapshot doesn't give a direct instantaneous %.
            # We'll report 0.00% for container CPU in snapshot summary as it's a rate metric.
            container_cpu_percent = 0.0

            # Get Memory Usage (bytes)
            container_mem_usage_bytes = stats['memory_stats'].get('usage', 0) if 'memory_stats' in stats else 0

            # For IO, return cumulative bytes for snapshot mode
            container_io_read_cumulative = 0
            container_io_write_cumulative = 0
            if 'blkio_stats' in stats and 'io_service_bytes_recursive' in stats['blkio_stats']:
                 current_io = {entry['op'].lower(): entry['value'] for entry in stats['blkio_stats']['io_service_bytes_recursive']}
                 container_io_read_cumulative = current_io.get('read', 0)
                 container_io_write_cumulative = current_io.get('write', 0)


            container_data = {
                'timestamp': current_time,
                'source': container_name,
                'cpu_percent': container_cpu_percent, # 0 for snapshot rate summary
                'mem_usage_bytes': container_mem_usage_bytes,
                'io_read_bytes': container_io_read_cumulative, # Cumulative for snapshot
                'io_write_bytes': container_io_write_cumulative # Cumulative for snapshot
            }
            data_points.append(container_data)

        except Exception as e:
            # Catch specific key errors for clarity if needed, but general Exception is safer
            print(f"Error getting snapshot stats for container '{container.name}' ({container.short_id}): {e}", file=sys.stderr)

    return data_points


# --- Main Monitoring Loop (for duration mode) ---
def run_monitoring_loop(client, duration, output_filename):
    all_data = []
    # Store previous stats along with timestamp for accurate rate calculation
    previous_host_io = None
    previous_host_timestamp = None
    previous_container_stats = {} # {container_name: {'stats': {...}, 'timestamp': t}}

    start_time = time.monotonic()
    end_time = start_time + duration

    os.makedirs(OUTPUT_DIR, exist_ok=True) # Ensure directory exists

    with open(output_filename, 'w', newline='') as csvfile:
        # Note: io_read/write are DELTAS/sec here when writing to CSV
        fieldnames = ['timestamp', 'source', 'cpu_percent', 'mem_usage_bytes', 'io_read_bytes', 'io_write_bytes']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

        print(f"Saving raw data to {output_filename}")

        # Initial sleep before the first measurement to get more accurate delta on first iteration
        time.sleep(MONITOR_INTERVAL)


        while time.monotonic() < end_time:
            current_time = time.time() # Wall clock time for data point timestamp
            current_monotonic_time = time.monotonic() # Monotonic time for loop duration check

            # --- Get Host Stats ---
            try:
                # psutil.cpu_percent(interval=None) after sleep gives % during the sleep interval
                host_cpu_percent = psutil.cpu_percent(interval=None)
                host_mem = psutil.virtual_memory()
                host_mem_usage_bytes = host_mem.used

                current_host_io = psutil.disk_io_counters()
                host_io_read_delta = 0
                host_io_write_delta = 0

                # Calculate delta bytes per second since last check using actual time delta
                if previous_host_io and previous_host_timestamp:
                    time_delta = current_time - previous_host_timestamp
                    if time_delta > 0:
                        host_io_read_delta = (current_host_io.read_bytes - previous_host_io.read_bytes) / time_delta
                        host_io_write_delta = (current_host_io.write_bytes - previous_host_io.write_bytes) / time_delta

                previous_host_io = current_host_io # Store for next iteration
                previous_host_timestamp = current_time # Store timestamp for next iteration


                host_data = {
                    'timestamp': current_time,
                    'source': 'host',
                    'cpu_percent': host_cpu_percent,
                    'mem_usage_bytes': host_mem_usage_bytes,
                    'io_read_bytes': host_io_read_delta, # Delta rate for CSV
                    'io_write_bytes': host_io_write_delta # Delta rate for CSV
                }
                all_data.append(host_data)
                writer.writerow(host_data)

            except Exception as e:
                print(f"Error getting host monitoring stats: {e}", file=sys.stderr)

            # --- Get Container Stats ---
            running_containers = []
            try:
                # Only list running containers as requested
                running_containers = client.containers.list(filters={"status": "running"})
            except Exception as e:
                print(f"Error listing containers: {e}", file=sys.stderr)

            current_container_full_stats = {} # {container_name: {'stats': {...}, 'timestamp': t}}
            for container in running_containers:
                try:
                    stats = container.stats(stream=False) # Get a snapshot
                    container_name = container.name
                    current_container_full_stats[container_name] = {'stats': stats, 'timestamp': current_time}


                    prev_full_stats = previous_container_stats.get(container_name)
                    prev_stats = prev_full_stats['stats'] if prev_full_stats else None
                    prev_timestamp = prev_full_stats['timestamp'] if prev_full_stats else None


                    # Calculate CPU % for container using delta over the interval
                    container_cpu_percent = calculate_container_cpu_percent(stats, prev_stats)

                    # Get Memory Usage (bytes)
                    container_mem_usage_bytes = stats['memory_stats'].get('usage', 0) if 'memory_stats' in stats else 0

                    # Calculate Block IO (bytes read/written per second) using delta over the interval
                    container_io_read_delta = 0
                    container_io_write_delta = 0

                    if ('blkio_stats' in stats and 'io_service_bytes_recursive' in stats['blkio_stats'] and
                        prev_stats and 'blkio_stats' in prev_stats and 'io_service_bytes_recursive' in prev_stats['blkio_stats'] and
                        prev_timestamp): # Ensure previous data exists

                         current_io = {entry['op'].lower(): entry['value'] for entry in stats['blkio_stats']['io_service_bytes_recursive']}
                         prev_io = {entry['op'].lower(): entry['value'] for entry in prev_stats['blkio_stats']['io_service_bytes_recursive']}

                         current_read = current_io.get('read', 0)
                         current_write = current_io.get('write', 0)
                         prev_read = prev_io.get('read', 0)
                         prev_write = prev_io.get('write', 0)

                         time_delta = current_time - prev_timestamp
                         if time_delta > 0:
                             container_io_read_delta = (current_read - prev_read) / time_delta
                             container_io_write_delta = (current_write - prev_write) / time_delta


                    container_data = {
                        'timestamp': current_time,
                        'source': container_name,
                        'cpu_percent': container_cpu_percent,
                        'mem_usage_bytes': container_mem_usage_bytes,
                        'io_read_bytes': container_io_read_delta, # Delta rate for CSV
                        'io_write_bytes': container_io_write_delta # Delta rate for CSV
                    }
                    all_data.append(container_data)
                    writer.writerow(container_data)

                except Exception as e:
                    # Catch specific key errors for clarity if needed, but general Exception is safer
                    print(f"Error getting monitoring stats for container '{container.name}' ({container.short_id}): {e}", file=sys.stderr)
                    # If stats fail, remove from previous_container_stats so it doesn't cause errors next time
                    previous_container_stats.pop(container.name, None)


            previous_container_stats = current_container_full_stats # Store for next iteration

            # Wait for the next interval based on monotonic time to keep loop roughly consistent
            time_to_sleep = MONITOR_INTERVAL - (time.monotonic() - current_monotonic_time)
            if time_to_sleep > 0:
                time.sleep(time_to_sleep)

        print("Monitoring complete.") # No summary message here, print_summary_table handles it
    return all_data, output_filename # Return filename too

# --- Function to generate and print the summary table ---
def print_summary_table(data_points, duration, sort_key=None, output_filename=None):
    if not data_points:
        print("No data collected.")
        return

    # Group data by source (host or container name)
    data_by_source = {}
    for data_point in data_points:
        source = data_point['source']
        if source not in data_by_source:
            data_by_source[source] = []
        data_by_source[source].append(data_point)

    summary_data = []

    # For each source, calculate summary stats
    for source, points in data_by_source.items():
        if not points:
            continue

        source_name = "Host System" if source == 'host' else source # Use name for containers

        cpu_values = [p['cpu_percent'] for p in points if p['cpu_percent'] is not None]
        mem_values = [p['mem_usage_bytes'] for p in points if p['mem_usage_bytes'] is not None]

        # IO values interpretation depends on mode (duration vs snapshot)
        if duration is None: # Snapshot mode
             # In snapshot, points list has only 1 element. Peak/Avg are just that value.
             # IO values are cumulative bytes read/written.
             peak_cpu = cpu_values[0] if cpu_values else 0.0 # Snapshot CPU percentage
             avg_cpu = cpu_values[0] if cpu_values else 0.0 # Snapshot CPU percentage
             peak_mem = mem_values[0] if mem_values else 0
             avg_mem = mem_values[0] if mem_values else 0
             peak_io_read = points[0]['io_read_bytes']
             avg_io_read = points[0]['io_read_bytes']
             peak_io_write = points[0]['io_write_bytes']
             avg_io_write = points[0]['io_write_bytes']
             io_unit = "" # No rate unit for cumulative
             read_header = "READ IO (Total)"
             write_header = "WRITE IO (Total)"
        else: # Monitoring mode (duration is not None)
            io_read_values = [p['io_read_bytes'] for p in points if p['io_read_bytes'] is not None]
            io_write_values = [p['io_write_bytes'] for p in points if p['io_write_bytes'] is not None]

            peak_cpu = max(cpu_values) if cpu_values else 0.0
            avg_cpu = statistics.mean(cpu_values) if cpu_values else 0.0
            peak_mem = max(mem_values) if mem_values else 0
            avg_mem = statistics.mean(mem_values) if mem_values else 0
            peak_io_read = max(io_read_values) if io_read_values else 0.0
            avg_io_read = statistics.mean(io_read_values) if io_read_values else 0.0
            peak_io_write = max(io_write_values) if io_write_values else 0.0
            avg_io_write = statistics.mean(io_write_values) if io_write_values else 0.0
            io_unit = "/s" # Rate unit for monitoring
            read_header = f"AVG READ IO{io_unit}"
            write_header = f"AVG WRITE IO{io_unit}"


        summary_data.append({
            'source': source_name,
            'avg_cpu': avg_cpu,
            'peak_cpu': peak_cpu,
            'avg_mem': avg_mem,
            'peak_mem': peak_mem,
            'avg_io_read': avg_io_read,
            'peak_io_read': peak_io_read,
            'avg_io_write': avg_io_write,
            'peak_io_write': peak_io_write,
            'io_unit': io_unit # Store unit
        })

    # --- Sort Summary Data ---
    if sort_key:
        reverse_sort = True # Sort descending (highest usage first)
        if sort_key == 'cpu':
            # Sort by average CPU, put Host first if it's sorted
            summary_data.sort(key=lambda x: x['avg_cpu'], reverse=reverse_sort)
        elif sort_key == 'ram':
            summary_data.sort(key=lambda x: x['avg_mem'], reverse=reverse_sort)
        elif sort_key == 'io':
            # Sort by total average IO (read + write)
            summary_data.sort(key=lambda x: x['avg_io_read'] + x['avg_io_write'], reverse=reverse_sort)
    else:
        # Default sort: Host first, then container names alphabetically
        def default_sort(item):
            if item['source'] == "Host System":
                return (0, item['source']) # Host comes first (tuple starts with 0)
            return (1, item['source'].lower()) # Containers come after (tuple starts with 1), sort alphabetically by name

        summary_data.sort(key=default_sort)


    # --- Print Table ---
    print("\n--- Resource Usage Summary ---")
    if duration is not None:
        print(f"Monitoring Duration: {duration} seconds")
    else:
         print("Snapshot taken at:", datetime.fromtimestamp(data_points[0]['timestamp']).strftime('%Y-%m-%d %H:%M:%S'))
    print("-" * 105) # Increased separator length again

    # Define headers based on mode
    if duration is None:
         headers = ["SOURCE", "CPU %", "RAM", read_header, write_header]
    else: # Monitoring mode
        headers = ["SOURCE", "AVG CPU %", "PEAK CPU %", "AVG RAM", "PEAK RAM",
                   read_header, f"PEAK READ IO{summary_data[0]['io_unit']}",
                   write_header, f"PEAK WRITE IO{summary_data[0]['io_unit']}"]


    # Prepare data rows (formatted strings)
    data_rows = []
    for item in summary_data:
        if duration is None: # Snapshot mode
            row = [
                item['source'],
                f"{item['avg_cpu']:.2f}", # Avg and Peak are the same in snapshot
                format_bytes(item['avg_mem']), # Avg and Peak are the same in snapshot
                format_bytes(item['avg_io_read']), # Cumulative
                format_bytes(item['avg_io_write']), # Cumulative
            ]
        else: # Monitoring mode
            row = [
                item['source'],
                f"{item['avg_cpu']:.2f}",
                f"{item['peak_cpu']:.2f}",
                format_bytes(item['avg_mem']),
                format_bytes(item['peak_mem']),
                format_bytes(item['avg_io_read']),
                format_bytes(item['peak_io_read']),
                format_bytes(item['avg_io_write']),
                format_bytes(item['peak_io_write']),
            ]
        data_rows.append(row)

    # Calculate column widths
    # Start with header widths
    col_widths = [len(h) for h in headers]
    # Update with max data width in each column
    for row in data_rows:
        for i, cell in enumerate(row):
            col_widths[i] = max(col_widths[i], len(str(cell)))

    # Print header row
    header_line = " | ".join(headers[i].ljust(col_widths[i]) for i in range(len(headers)))
    print(header_line)
    print("-+-".join("-" * col_widths[i] for i in range(len(headers)))) # Separator line

    # Print data rows
    for row in data_rows:
        row_line = " | ".join(str(row[i]).ljust(col_widths[i]) for i in range(len(headers)))
        print(row_line)

    print("-" * 105) # Increased separator length
    if duration is not None and output_filename: # Only show raw data file path in monitoring mode
        print(f"Raw data saved to: {output_filename}")
    print("--- End of Summary ---")


# --- Script Entry Point ---
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Monitor host and Docker container resource usage.")
    parser.add_argument(
        "duration",
        nargs='?', # Makes the argument optional
        type=parse_duration,
        help="Monitoring duration (e.g., 60s, 5m). If omitted, takes a single snapshot."
    )
    parser.add_argument(
        "-c", "--sort-cpu", action="store_true", dest='sort_cpu', help="Sort by average CPU usage (descending)."
    )
    parser.add_argument(
        "-m", "--sort-ram", action="store_true", dest='sort_ram', help="Sort by average RAM usage (descending)."
    )
    parser.add_argument(
        "-i", "--sort-io", action="store_true", dest='sort_io', help="Sort by average total I/O rate (read+write) (descending)."
    )

    args = parser.parse_args()

    # Determine sorting key
    sort_key = None
    if args.sort_cpu:
        sort_key = 'cpu'
    elif args.sort_ram:
        sort_key = 'ram'
    elif args.sort_io:
        sort_key = 'io'

    # Validate sorting flags - only one allowed
    if sum([args.sort_cpu, args.sort_ram, args.sort_io]) > 1:
        print("Error: Only one sorting flag (-c, -m, -i) can be used at a time.", file=sys.stderr)
        sys.exit(1)

    try:
        client = docker.from_env()
        client.ping() # Check if docker is running
    except docker.errors.DockerException as e:
        print(f"Error connecting to Docker: {e}", file=sys.stderr)
        print("Please ensure Docker is running and the user has permission.", file=sys.stderr)
        sys.exit(1)

    if args.duration is not None:
        # --- Duration Monitoring Mode ---
        monitor_duration = args.duration
        print(f"Starting monitoring for {monitor_duration} seconds...")
        # Generate filename before monitoring starts
        timestamp_str = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_filename = os.path.join(OUTPUT_DIR, f"monitoring_data_{timestamp_str}.csv")

        all_data, output_filename_used = run_monitoring_loop(client, monitor_duration, output_filename)
        print_summary_table(all_data, duration=monitor_duration, sort_key=sort_key, output_filename=output_filename_used)

    else:
        # --- Single Snapshot Mode ---
        print("Taking a single snapshot...")
        snapshot_data = collect_snapshot(client)
        # In snapshot mode, the IO values are cumulative. Pass duration=None to indicate snapshot mode
        print_summary_table(snapshot_data, duration=None, sort_key=sort_key)
