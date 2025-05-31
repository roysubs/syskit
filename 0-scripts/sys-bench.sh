#!/bin/bash
# Author: Roy Wiseman 2025-05

# sys-bench.sh - Simple system benchmark script
# Requirements: sysbench, fio, iperf3, curl, jq, lshw,
#               lm-sensors, smartmontools, speedtest-cli

# --- FIO_SAFETY_CHECK_START ---
# This block is to prevent 'fio' commands with 'rw=readwrite' or 'rw=write' in the script below
# the FIO_SAFETY_CHECK_END marker, as these will destroy any system they are run on.
# This is a critical safety measure to prevent accidental data destruction.
SCRIPT_CONTENT=$(cat "$0")
FIO_PROTECTION_TEST_END_LINE=$(echo "$SCRIPT_CONTENT" | grep -n "^# --- FIO_SAFETY_CHECK_END ---" | cut -d: -f1)

if [ -n "$FIO_PROTECTION_TEST_END_LINE" ]; then
    # Get content after the marker line
    CONTENT_AFTER_MARKER=$(echo "$SCRIPT_CONTENT" | tail -n +$((FIO_PROTECTION_TEST_END_LINE + 1)))
    if echo "$CONTENT_AFTER_MARKER" | grep -q -E "rw=(readwrite|write)"; then
        echo -e "\033[1m\033[31mERROR: A restricted 'rw=readwrite' or 'rw=write' string was found in the body of the script.\nIf used with 'fio', these can completely destroy all data on a system. Ensure that any\nstrings like this are removed from the body of the script. Exiting to prevent data loss.\033[0m" >&2
        exit 1
    else
        echo -e "${BOLD}No instances of 'rw=readwrite' or 'rw=write' were found in the script.${RESET}"
    fi
fi
# --- FIO_SAFETY_CHECK_END ---
# All fio commands below this line will be checked for destructive patterns.
# Do NOT remove or modify the line above unless you understand the safety implications.

OVERALL_START_TIME=$(date +%s)

VERBOSE=0
for arg in "$@"; do
  if [[ "$arg" == "--verbose" || "$arg" == "-v" ]]; then
    VERBOSE=1
  fi
done

log() {
  echo -e "$1"
}

vlog() {
  if [[ $VERBOSE -eq 1 ]]; then
    echo -e "$1"
  fi
}

BOLD="\033[1m"
RESET="\033[0m"

# Helper function to check command availability more robustly
is_command_available() {
    local cmd_name="$1"
    if command -v "$cmd_name" &>/dev/null; then return 0; fi
    # Check common sbin paths for tools like smartctl
    if [[ -x "/usr/sbin/$cmd_name" ]]; then return 0; fi
    if [[ -x "/sbin/$cmd_name" ]]; then return 0; fi
    if [[ -x "/usr/local/sbin/$cmd_name" ]]; then return 0; fi
    return 1
}

install_dependency() {
    local package_name="$1"
    local command_name="$2"

    if ! is_command_available "$command_name"; then
        local SUDO_CMD=""
        if [[ $EUID -ne 0 ]]; then
            if ! command -v "sudo" &>/dev/null; then
                log "${BOLD}Warning: 'sudo' command not found, and script not run as root.${RESET}"
                log "Installation of '$package_name' for '$command_name' will likely fail without sudo privileges."
                # Fallthrough to ask, but apt-get will likely fail
            fi
            SUDO_CMD="sudo"
        fi

        echo -e "${BOLD}'$command_name' (from '$package_name') appears to be missing or not in PATH.${RESET}"
        read -r -p "Install '$package_name'? [Y/n] " yn
        if [[ $yn =~ ^[Yy]$ ]] || [[ -z $yn ]]; then
            log "Installing $package_name..."
            if $SUDO_CMD apt-get update && $SUDO_CMD apt-get install -y "$package_name"; then
                log "$package_name installed successfully (or was already present)."
                # Re-check availability after install
                if ! is_command_available "$command_name"; then
                    log "${BOLD}Warning: $package_name installed, but command '$command_name' still not found in typical PATH locations. You might need to adjust your PATH or use 'sudo $command_name' explicitly.${RESET}"
                fi
            else
                log "${BOLD}Failed to install $package_name. Exiting.${RESET}"
                exit 1
            fi
        else
            log "'$command_name' is required by this script. Exiting."
            exit 1
        fi
    fi
}

# Install dependencies using the new function
install_dependency "coreutils" "nproc"
install_dependency "sysbench" "sysbench"
install_dependency "fio" "fio"
install_dependency "iperf3" "iperf3"
install_dependency "curl" "curl"
install_dependency "jq" "jq"
install_dependency "lshw" "lshw"
install_dependency "lm-sensors" "sensors"
install_dependency "smartmontools" "smartctl"
install_dependency "speedtest" "speedtest" # Note: For Ookla official, repo setup might be needed first

NUM_THREADS=$(nproc 2>/dev/null || echo 1)

log "${BOLD}🖥️  SYSTEM INFO${RESET}"
uname -a
LSHW_CMD="lshw"
if [[ $EUID -ne 0 ]] && is_command_available "sudo"; then
    LSHW_CMD="sudo lshw"
fi
$LSHW_CMD -short -C memory -C processor -C disk -C display 2>/dev/null || lshw -short -C memory -C processor -C disk -C display

echo
log "${BOLD}🧠 CPU${RESET}"
log "Sysbench CPU Test (Prime numbers calculation, ${NUM_THREADS} thread(s))"
CPU_OUT=$(sysbench cpu --cpu-max-prime=20000 --threads="$NUM_THREADS" --time=10 run 2>/dev/null)
CPU_EVENTS_PER_SEC=$(echo "$CPU_OUT" | grep 'events per second:' | awk '{print $4}')
TOTAL_TIME_CPU=$(echo "$CPU_OUT" | grep 'total time:' | awk '{print $3}')

if [[ -n "$TOTAL_TIME_CPU" ]]; then log "  Test Duration: ${TOTAL_TIME_CPU}"; else log "  Test Duration: 10s (configured)"; fi
if [[ -n "$CPU_EVENTS_PER_SEC" ]]; then log "  Performance:    ${CPU_EVENTS_PER_SEC} events/sec"; else log "  Could not parse CPU events/sec."; echo "$CPU_OUT" | head -n 5; fi
vlog "$CPU_OUT"

echo
log "${BOLD}🧵 RAM${RESET}"
log "Sysbench RAM Test (Read, ${NUM_THREADS} thread(s))"
RAM_OUT=$(sysbench memory --memory-block-size=1M --memory-scope=global --memory-total-size=4G --memory-oper=read --time=10 --threads="$NUM_THREADS" run 2>/dev/null)
OPERATIONS_INFO_RAM=$(echo "$RAM_OUT" | grep "Total operations:")
TRANSFER_INFO_RAM=$(echo "$RAM_OUT" | grep "MiB transferred")
LATENCY_AVG_RAM=$(echo "$RAM_OUT" | awk '/Latency statistics:/,/^\s*$/' | grep 'avg:' | awk '{printf "%.3f %s", $2, $3}')
TEST_DURATION_RAM=$(echo "$RAM_OUT" | grep 'total time:' | awk '{print $3}')

if [[ -n "$TEST_DURATION_RAM" ]]; then log "  Test Duration: $TEST_DURATION_RAM"; else log "  Test Duration: 10s (configured)"; fi
if [[ -n "$OPERATIONS_INFO_RAM" ]]; then log "  $(echo "$OPERATIONS_INFO_RAM" | awk -F'[ ():]+' '{printf "Operations: %s (%s %s %s)", $3, $5, $6, $7}')"; fi
if [[ -n "$TRANSFER_INFO_RAM" ]]; then TRANSFER_TOTAL_MIB=$(echo "$TRANSFER_INFO_RAM" | awk '{print $1}'); TRANSFER_SPEED_UNIT=$(echo "$TRANSFER_INFO_RAM" | awk -F'[()]' '{print $2}'); log "  Transfer: ${TRANSFER_TOTAL_MIB} MiB (${TRANSFER_SPEED_UNIT})"; fi
if [[ -n "$LATENCY_AVG_RAM" && "$LATENCY_AVG_RAM" != "0.000 " && "$LATENCY_AVG_RAM" != "0.000 ms" && "$LATENCY_AVG_RAM" != "0.000 us"  ]]; then log "  Avg Read Latency: $LATENCY_AVG_RAM"; else log "  Avg Read Latency: (not available or negligible)"; fi
vlog "$RAM_OUT"

echo
log "${BOLD}💾 DISK${RESET}"
log "${BOLD}Note: For Direct I/O tests on raw devices (e.g., /dev/sda), this script/fio may need to be run with 'sudo'.${RESET}"
log "${BOLD}Warning: Direct I/O tests on raw devices will be READ-ONLY to prevent data loss.${RESET}"
for DISK_PATH_RAW in /dev/sd[a-z]; do
  if [[ -b "$DISK_PATH_RAW" ]]; then
    MODEL=$(lsblk -no MODEL "$DISK_PATH_RAW" | head -n1)
    SIZE=$(lsblk -no SIZE "$DISK_PATH_RAW" | head -n1)
    log "📦 ${BOLD}$DISK_PATH_RAW ($MODEL, $SIZE)${RESET}"

    log "  ➤ Direct I/O READ-ONLY test (raw device)..."
    # fio command for raw device test, explicitly set to READ-ONLY
    FIO_CMD_RAW="fio --name=rawtest --filename=$DISK_PATH_RAW --direct=1 --rw=read --bs=4k --size=256M --numjobs=1 --time_based --runtime=10s --group_reporting --iodepth=32"
    
    # If not root, try with sudo for fio raw test
    if [[ $EUID -ne 0 ]] && is_command_available "sudo"; then
        RAW_OUT_FIO=$(sudo $FIO_CMD_RAW 2>/dev/null)
    else
        RAW_OUT_FIO=$($FIO_CMD_RAW 2>/dev/null) # Run as current user if already root or no sudo
    fi

    if [[ -n "$RAW_OUT_FIO" ]]; then
        # Filter output for read metrics, as write section won't exist in read-only test
        FILTERED_RAW_OUT=$(echo "$RAW_OUT_FIO" | grep -E '^\s*(read:|READ: bw=)')
        if [[ -n "$FILTERED_RAW_OUT" ]]; then
            echo "$FILTERED_RAW_OUT" | sed -e 's/^/    /' -e 's/^\s*read:/Direct Read:/' -e 's/^\s*READ: bw=/Direct Sum. READ:/'
        else
            log "    ${BOLD}(Direct I/O read test ran but no standard metrics parsed.)${RESET}"
            log "    First few lines of FIO output for Direct I/O on $DISK_PATH_RAW:"
            echo "$RAW_OUT_FIO" | head -n 10 | sed 's/^/    | /'
            log "    (Ensure adequate permissions for $DISK_PATH_RAW if issues persist. Full FIO output in verbose mode.)"
        fi
    else
        log "    ${BOLD}(Direct I/O read test produced no output or failed.)${RESET} Ensure script has permissions for $DISK_PATH_RAW (e.g. run with sudo) or device supports test."
        log "    Attempted command: $FIO_CMD_RAW (or with sudo if not root)"
    fi
    vlog "$RAW_OUT_FIO"

    # Filesystem test logic
    FOUND_MOUNTPOINT=""
    for PART_PATH_LOOKUP in ${DISK_PATH_RAW}[0-9]*; do
        if [[ -b "$PART_PATH_LOOKUP" ]]; then
            CURRENT_MP=$(lsblk -no MOUNTPOINT "$PART_PATH_LOOKUP" | grep -v '^$' | head -n1)
            if [[ -n "$CURRENT_MP" && -d "$CURRENT_MP" ]]; then if df "$CURRENT_MP" --output=avail -B 1 | awk 'NR==2 && $1 > 1610612736' > /dev/null; then FOUND_MOUNTPOINT="$CURRENT_MP"; break; fi; fi
        fi
    done
    if [[ -z "$FOUND_MOUNTPOINT" ]]; then MAIN_DISK_MP=$(lsblk -no MOUNTPOINT "$DISK_PATH_RAW" | grep -v '^$' | head -n1); if [[ -n "$MAIN_DISK_MP" && -d "$MAIN_DISK_MP" ]]; then if df "$MAIN_DISK_MP" --output=avail -B 1 | awk 'NR==2 && $1 > 1610612736' > /dev/null; then FOUND_MOUNTPOINT="$MAIN_DISK_MP"; fi; fi; fi

    if [[ -z "$FOUND_MOUNTPOINT" ]]; then
        log "  ➤ Filesystem test (No suitable mounted partition with >1.5GB free space found for $DISK_PATH_RAW, skipping)"
    else
        MOUNTPOINT="$FOUND_MOUNTPOINT"
        log "  ➤ Filesystem test @ $MOUNTPOINT"
        TEST_FILE="$MOUNTPOINT/sys_bench_fio_test_file.$$"
        if touch "$TEST_FILE" 2>/dev/null; then
            # fio command for filesystem test, explicitly set to READ-ONLY
            FS_OUT_FIO=$(fio --name=fsbench --filename="$TEST_FILE" --size=1G --rw=read --bs=4k --runtime=10s --time_based --numjobs=1 --group_reporting --iodepth=32 --direct=0 2>/dev/null)
            rm -f "$TEST_FILE"
            if [[ -n "$FS_OUT_FIO" ]]; then
                # Filter output for read metrics
                FILTERED_FS_OUT=$(echo "$FS_OUT_FIO" | grep -E '^\s*(read:|READ: bw=)')
                if [[ -n "$FILTERED_FS_OUT" ]]; then echo "$FILTERED_FS_OUT" | sed -e 's/^/    /' -e 's/^\s*read:/FS Read:/' -e 's/^\s*READ: bw=/FS Sum. READ:/'; else log "    (FS test ran but no metrics parsed. Verbose for FIO output.)"; fi
            else log "    (FS test produced no output or failed. Check $MOUNTPOINT.)"; fi
            vlog "$FS_OUT_FIO"
        else log "    (Cannot write to $TEST_FILE @ $MOUNTPOINT, skipping FS test.)"; fi
    fi
    echo
  fi
done

log "${BOLD}🌐 NETWORK (Local)${RESET}"
if is_command_available "iperf3"; then
    log "Checking for local iperf3 server (localhost:5201)..."
    if iperf3 -c localhost -t 1 -p 5201 &>/dev/null; then
      log "Local iperf3 server found. Running 10s test..."
      NET_OUT=$(iperf3 -c localhost -t 10 -p 5201)
      echo "$NET_OUT" | grep -E '\[ *[0-9A-Z]+\] +0.00-[0-9.]+ +sec .* sender'
      echo "$NET_OUT" | grep -E '\[ *[0-9A-Z]+\] +0.00-[0-9.]+ +sec .* receiver'
      log "Duration: 10s (configured)"
      vlog "$NET_OUT"
    else
      log "iperf3 local server not running/reachable on localhost:5201. Skipping."
      log "  You can start a server with: iperf3 -s"
    fi
else
    log "iperf3 command not found. Skipping local network test."
fi


echo
log "${BOLD}🌡️  TEMPERATURES${RESET}"
if is_command_available "sensors"; then
  TEMP_OUT=$(sensors)
  echo "$TEMP_OUT" | grep -Pi 'Package id|Core [0-9]+:|Composite:|Adapter:|temp[0-9]+:|Tdie:|CPU Temp|GPU Temp|Physical id|pch_|soc_phy|fan[0-9]' | sed 's/^+//' | sed 's/^[[:space:]]*//'
  vlog "$TEMP_OUT"
else
  log "sensors command not found. Skipping temperature readings."
fi

echo
log "${BOLD}🚀 INTERNET SPEED TEST (using Ookla speedtest-cli)${RESET}"
if is_command_available "speedtest"; then
  log "Running Ookla Speedtest CLI (this may take a minute)..."
  SPEEDTEST_JSON_OUTPUT=$(timeout 120s speedtest --accept-license --accept-gdpr -f json 2>/dev/null)
  SPEEDTEST_EXIT_CODE=$?

  if [[ $SPEEDTEST_EXIT_CODE -eq 0 && -n "$SPEEDTEST_JSON_OUTPUT" ]] && jq -e . >/dev/null 2>&1 <<<"$SPEEDTEST_JSON_OUTPUT"; then
    PING=$(echo "$SPEEDTEST_JSON_OUTPUT" | jq -r '.ping.latency')
    DOWNLOAD_BPS=$(echo "$SPEEDTEST_JSON_OUTPUT" | jq -r '.download.bandwidth')
    UPLOAD_BPS=$(echo "$SPEEDTEST_JSON_OUTPUT" | jq -r '.upload.bandwidth')
    PACKET_LOSS_RAW=$(echo "$SPEEDTEST_JSON_OUTPUT" | jq -r '.packetLoss')
    DOWNLOAD_MBPS=$(awk -v bps="$DOWNLOAD_BPS" 'BEGIN {if (bps > 0 && bps != "null") printf "%.2f", bps * 8 / 1000000.0; else print "0.00"}')
    UPLOAD_MBPS=$(awk -v bps="$UPLOAD_BPS" 'BEGIN {if (bps > 0 && bps != "null") printf "%.2f", bps * 8 / 1000000.0; else print "0.00"}')
    PACKET_LOSS_DISPLAY="N/A"; if [[ "$PACKET_LOSS_RAW" != "null" && -n "$PACKET_LOSS_RAW" ]]; then PACKET_LOSS_DISPLAY="${PACKET_LOSS_RAW}%"; fi
    RESULT_URL=$(echo "$SPEEDTEST_JSON_OUTPUT" | jq -r '.result.url')
    log "  Ping: ${PING} ms"; log "  Download: ${DOWNLOAD_MBPS} Mbps"; log "  Upload: ${UPLOAD_MBPS} Mbps"; log "  Packet Loss: ${PACKET_LOSS_DISPLAY}"
    if [[ "$RESULT_URL" != "null" && -n "$RESULT_URL" ]]; then log "  Result URL: ${RESULT_URL}"; fi
    vlog "$SPEEDTEST_JSON_OUTPUT"
  elif [[ $SPEEDTEST_EXIT_CODE -eq 124 ]]; then log "  Ookla Speedtest CLI timed out after 120 seconds."
  else
    log "  Ookla Speedtest CLI failed, produced no valid JSON, or was not found correctly."
    log "  Exit code: $SPEEDTEST_EXIT_CODE."
    log "  If 'speedtest' command failed due to not being installed via 'apt-get install speedtest',"
    log "  ensure you have first set up the Ookla repository for your system."
    log "  (e.g., for Debian/Ubuntu: curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash )"
    vlog "Output was: $SPEEDTEST_JSON_OUTPUT"
  fi
else
  log "Ookla speedtest-cli (command: speedtest) not found or not installed via 'install_dependency'."
  log "  If you skipped installation: for Ookla CLI on Debian/Ubuntu:"
  log "  1. curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash"
  log "  2. sudo apt install speedtest"
  log "  Then re-run this script. For other systems, check https://www.speedtest.net/apps/cli"
fi


echo
OVERALL_END_TIME=$(date +%s)
TOTAL_BENCHMARK_DURATION=$((OVERALL_END_TIME - OVERALL_START_TIME))
log "${BOLD}🏁 Total Benchmark Duration: ${TOTAL_BENCHMARK_DURATION}s${RESET}"

