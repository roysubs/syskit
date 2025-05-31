#!/bin/bash
# Author: Roy Wiseman 2025-02

# Application Process Monitoring Tool

# Text formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
RESET="\033[0m"

# Help message
if [[ "$1" == "-h" || "$1" == "--help" || -z "$1" ]]; then
    echo -e "${BOLD}Application Process Monitoring Tool${RESET}"
    echo "This tool monitors filesystem changes, CPU/memory usage, and timing information"
    echo "before, during, and after running an application."
    echo
    echo "Usage:"
    echo "  ${0##*/} <command_to_run> [arguments]"   # $(basename $0) replacement
    echo
    echo "Example:"
    echo "  ${0##*/} angband"
    echo "  ${0##*/} \"firefox https://example.com\""
    echo
    exit 0
fi

# Check if application exists
APP_PATH=$(command -v "$1")
if [[ -z "$APP_PATH" ]]; then
    echo -e "${RED}Error: Command '$1' not found${RESET}"
    echo "Please specify a valid application to monitor"
    exit 1
fi

# Create a temporary directory for our monitoring files
TEMP_DIR=$(mktemp -d)
chmod 755 "$TEMP_DIR"
BEFORE_FILES="$TEMP_DIR/before_files.log"
AFTER_FILES="$TEMP_DIR/after_files.log"
CHANGED_FILES="$TEMP_DIR/changed_files.log"
COMMAND_OUTPUT="$TEMP_DIR/command_output.log"
MONITORING_DATA="$TEMP_DIR/monitoring_data.log"

# Save the application command and arguments
APP_CMD="$@"
APP_NAME=$(basename "$1")

# =====================================================
# Helper functions
# =====================================================

# Format a timestamp
format_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Get current disk usage for home directory
get_disk_usage() {
    du -sh "$HOME" 2>/dev/null | awk '{print $1}'
}

# Get CPU and memory usage of a process
get_process_usage() {
    local PID=$1
    # Get CPU and memory usage
    ps -p $PID -o %cpu=,%mem= 2>/dev/null || echo "0.0 0.0"
}

# Print section header
print_header() {
    echo -e "\n${BOLD}${BLUE}$1${RESET}"
    echo -e "${BLUE}$(printf '%.s-' $(seq 1 ${#1}))${RESET}\n"
}

# =====================================================
# Pre-run monitoring
# =====================================================

print_header "Starting Filesystem Monitoring"
echo -e "${YELLOW}Target Application:${RESET} $APP_CMD"

# Record start time
START_TIME=$(date +%s)
START_TIMESTAMP=$(format_timestamp)
echo -e "${CYAN}Start Time:${RESET} $START_TIMESTAMP"

# Get initial disk usage
BEFORE_DISK_USAGE=$(get_disk_usage)
echo -e "${CYAN}Initial Disk Usage (Home):${RESET} $BEFORE_DISK_USAGE"

# Start filesystem scan
echo -e "\n${YELLOW}Scanning filesystem before running the application...${RESET}"
SCAN_START_TIME=$(date +%s)
find "$HOME" -type f -printf '%T@ %s %p\n' 2>/dev/null | sort > "$BEFORE_FILES"
SCAN_END_TIME=$(date +%s)
SCAN_DURATION=$((SCAN_END_TIME - SCAN_START_TIME))
echo -e "${GREEN}Filesystem scan completed in ${SCAN_DURATION} seconds${RESET}"
TOTAL_FILES=$(wc -l < "$BEFORE_FILES")
echo -e "${CYAN}Total files scanned:${RESET} $TOTAL_FILES"

# =====================================================
# Run the application with monitoring
# =====================================================

print_header "Running Application"
echo -e "${YELLOW}Command:${RESET} $APP_CMD"
echo -e "${YELLOW}Press Ctrl+C to terminate if the application doesn't exit properly${RESET}"

# Get initial resource stats
echo -e "\n${CYAN}Resource Usage Before Start:${RESET}"
echo "CPU Usage (System): $(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')%"
echo "Memory Free: $(free -h | grep Mem | awk '{print $4}')"
echo "Memory Used: $(free -h | grep Mem | awk '{print $3}')"

# Start CPU/memory monitoring in background
echo "timestamp,cpu_usage,memory_usage" > "$MONITORING_DATA"
(
    while true; do
        # Find all PIDs related to our application
        APP_PIDS=$(pgrep -f "$APP_NAME" 2>/dev/null)
        if [[ -z "$APP_PIDS" ]]; then
            sleep 1
            # Double check before deciding the app has terminated
            APP_PIDS=$(pgrep -f "$APP_NAME" 2>/dev/null)
            if [[ -z "$APP_PIDS" ]]; then
                break
            fi
        fi
        
        # Sum CPU/memory for all matching processes
        TOTAL_CPU=0
        TOTAL_MEM=0
        for pid in $APP_PIDS; do
            USAGE=$(ps -p $pid -o %cpu=,%mem= 2>/dev/null)
            if [[ -n "$USAGE" ]]; then
                CPU=$(echo $USAGE | awk '{print $1}')
                MEM=$(echo $USAGE | awk '{print $2}')
                TOTAL_CPU=$(echo "$TOTAL_CPU + $CPU" | bc)
                TOTAL_MEM=$(echo "$TOTAL_MEM + $MEM" | bc)
            fi
        done
        
        # Only record non-zero values
        if [[ $(echo "$TOTAL_CPU > 0 || $TOTAL_MEM > 0" | bc) -eq 1 ]]; then
            echo "$(date +%s),$TOTAL_CPU,$TOTAL_MEM" >> "$MONITORING_DATA"
        fi
        sleep 1
    done
) &
MONITOR_PID=$!

# Record application start time
APP_START_TIME=$(date +%s)
APP_START_TIMESTAMP=$(format_timestamp)
echo -e "\n${GREEN}Application started at: $APP_START_TIMESTAMP${RESET}"

# Run the application
$APP_CMD > "$COMMAND_OUTPUT" 2>&1

# Record application end time
APP_END_TIME=$(date +%s)
APP_END_TIMESTAMP=$(format_timestamp)
APP_DURATION=$((APP_END_TIME - APP_START_TIME))
echo -e "\n${GREEN}Application finished at: $APP_END_TIMESTAMP${RESET}"
echo -e "${GREEN}Application ran for: $APP_DURATION seconds${RESET}"

# Stop the monitoring
kill $MONITOR_PID 2>/dev/null

# Get final resource stats
echo -e "\n${CYAN}Resource Usage After Exit:${RESET}"
echo "CPU Usage (System): $(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')%"
echo "Memory Free: $(free -h | grep Mem | awk '{print $4}')"
echo "Memory Used: $(free -h | grep Mem | awk '{print $3}')"

# =====================================================
# Post-run monitoring
# =====================================================

print_header "Post-Run Analysis"

# Get final disk usage
AFTER_DISK_USAGE=$(get_disk_usage)
echo -e "${CYAN}Final Disk Usage (Home):${RESET} $AFTER_DISK_USAGE"

# Scan filesystem after running
echo -e "\n${YELLOW}Scanning filesystem after running the application...${RESET}"
SCAN2_START_TIME=$(date +%s)
find "$HOME" -type f -printf '%T@ %s %p\n' 2>/dev/null | sort > "$AFTER_FILES"
SCAN2_END_TIME=$(date +%s)
SCAN2_DURATION=$((SCAN2_END_TIME - SCAN2_START_TIME))
echo -e "${GREEN}Filesystem scan completed in ${SCAN2_DURATION} seconds${RESET}"

# Calculate and show differences
echo -e "\n${YELLOW}Analyzing filesystem changes...${RESET}"
echo -e "${BOLD}${CYAN}Files created or modified:${RESET}"
echo -e "╔═══════════════════════════════════════════════════════════════════════════"
echo -e "║ ${BOLD}MODIFICATION TIME       SIZE       PATH${RESET}"
echo -e "╠═══════════════════════════════════════════════════════════════════════════"

# Extract changed files with timestamp, size and path
comm -13 "$BEFORE_FILES" "$AFTER_FILES" > "$CHANGED_FILES"
NUM_CHANGED=$(wc -l < "$CHANGED_FILES")

# Display the changed files with details
if [[ $NUM_CHANGED -gt 0 ]]; then
    while IFS=' ' read -r timestamp size path; do
        # Convert timestamp to human readable format
        date_str=$(date -d @"$timestamp" "+%Y-%m-%d %H:%M:%S")
        
        # Format size to be human readable
        if [[ $size -gt 1048576 ]]; then
            size_str=$(echo "scale=2; $size/1048576" | bc)" MB"
        elif [[ $size -gt 1024 ]]; then
            size_str=$(echo "scale=2; $size/1024" | bc)" KB"
        else
            size_str="$size B"
        fi
        
        printf "║ %-23s %-10s %s\n" "$date_str" "$size_str" "$path"
    done < "$CHANGED_FILES"
else
    echo -e "║ ${YELLOW}No files were created or modified${RESET}"
fi

echo -e "╠═══════════════════════════════════════════════════════════════════════════"
echo -e "║ ${BOLD}Total files modified:${RESET} $NUM_CHANGED"
echo -e "╚═══════════════════════════════════════════════════════════════════════════"

# Calculate peak CPU and memory usage
if [[ -s "$MONITORING_DATA" ]]; then
    PEAK_CPU=$(tail -n +2 "$MONITORING_DATA" | cut -d, -f2 | sort -nr | head -1)
    PEAK_MEM=$(tail -n +2 "$MONITORING_DATA" | cut -d, -f3 | sort -nr | head -1)
    AVG_CPU=$(tail -n +2 "$MONITORING_DATA" | cut -d, -f2 | awk '{sum+=$1} END {if(NR>0) print sum/NR; else print "0"}')
    AVG_MEM=$(tail -n +2 "$MONITORING_DATA" | cut -d, -f3 | awk '{sum+=$1} END {if(NR>0) print sum/NR; else print "0"}')
    
    echo -e "\n${CYAN}Resource Usage Summary:${RESET}"
    printf "Peak CPU Usage: %6.1f%%\n" $PEAK_CPU
    printf "Peak Memory Usage: %6.1f%%\n" $PEAK_MEM
    printf "Average CPU Usage: %6.1f%%\n" $AVG_CPU
    printf "Average Memory Usage: %6.1f%%\n" $AVG_MEM
fi

# =====================================================
# Generate summary report
# =====================================================

# Create a simple ASCII box for the summary
print_header "Summary Report"

echo -e "┌───────────────────────────────────────────────────────────────────────────"
echo -e "│ ${BOLD}${BLUE}FILESYSTEM MONITORING SUMMARY${RESET}"
echo -e "├───────────────────────────────────────────────────────────────────────────"
printf "│ %-20s │ %s\n" "Application" "$APP_CMD"
echo -e "├───────────────────────────────────────────────────────────────────────────"
printf "│ %-20s │ %s\n" "Start Time" "$APP_START_TIMESTAMP"
printf "│ %-20s │ %s\n" "End Time" "$APP_END_TIMESTAMP"
printf "│ %-20s │ %s\n" "Runtime" "$APP_DURATION seconds"
echo -e "├───────────────────────────────────────────────────────────────────────────"
printf "│ %-20s │ %s\n" "Disk Usage Before" "$BEFORE_DISK_USAGE"
printf "│ %-20s │ %s\n" "Disk Usage After" "$AFTER_DISK_USAGE"
printf "│ %-20s │ %s\n" "Files Changed" "$NUM_CHANGED"
echo -e "├───────────────────────────────────────────────────────────────────────────"
printf "│ %-20s │ %s\n" "Peak CPU Usage" "${PEAK_CPU:-N/A}%"
printf "│ %-20s │ %s\n" "Peak Memory Usage" "${PEAK_MEM:-N/A}%"
printf "│ %-20s │ %s\n" "Avg CPU Usage" "$(printf "%.1f" ${AVG_CPU:-0})%"
printf "│ %-20s │ %s\n" "Avg Memory Usage" "$(printf "%.1f" ${AVG_MEM:-0})%"
echo -e "└───────────────────────────────────────────────────────────────────────────"

# Display resource usage over time if available
if [[ -s "$MONITORING_DATA" && $(wc -l < "$MONITORING_DATA") -gt 2 ]]; then
    # Check if we actually gathered any useful data
    HAS_DATA=0
    tail -n +2 "$MONITORING_DATA" | while IFS=, read timestamp cpu mem; do
        if (( $(echo "$cpu > 0.1 || $mem > 0.1" | bc -l) )); then
            HAS_DATA=1
            break
        fi
    done
    
    if [[ $HAS_DATA -eq 1 ]]; then
        echo -e "\n${BOLD}${BLUE}Resource Usage Timeline (App Process Only)${RESET}"
        echo -e "Time      CPU%    MEM%"
        echo -e "─────────────────────────"
        
        # Display samples with non-zero values
        tail -n +2 "$MONITORING_DATA" | while IFS=, read timestamp cpu mem; do
            if (( $(echo "$cpu > 0.1 || $mem > 0.1" | bc -l) )); then
                time_str=$(date -d @"$timestamp" "+%H:%M:%S")
                printf "%-9s %-7s %-7s\n" "$time_str" "$(printf "%.1f" $cpu)" "$(printf "%.1f" $mem)"
            fi
        done
    fi
fi

# =====================================================
# Final output and cleanup
# =====================================================

print_header "Monitoring Complete"

# Clean up temporary files
rm -rf "$TEMP_DIR"

echo -e "${BOLD}${GREEN}Monitoring completed successfully${RESET}"
