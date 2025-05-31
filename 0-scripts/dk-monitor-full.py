#!/usr/bin/env python3
# Author: Roy Wiseman 2025-03
import subprocess
import json
import shutil
import sys
import time
import argparse
import re
from collections import defaultdict

def check_docker():
    if not shutil.which("docker"):
        print("Docker is not installed or not in your PATH.")
        sys.exit(1)

def parse_cpu(cpu_str):
    try:
        return float(cpu_str.strip('%'))
    except:
        return 0.0

def parse_mem(mem_str):
    try:
        base = mem_str.strip().split('/')[0].strip()
        match = re.match(r"([\d.]+)([KMG]?i?B)", base)
        if not match:
            return 0.0
        value, unit = match.groups()
        value = float(value)
        unit = unit.lower()
        if unit.startswith("g"):
            return value * 1024
        elif unit.startswith("m"):
            return value
        elif unit.startswith("k"):
            return value / 1024
        else:
            return value
    except:
        return 0.0

def parse_io(io_str):
    try:
        rx_str, tx_str = io_str.split('/')
        rx = parse_mem(rx_str.strip())
        tx = parse_mem(tx_str.strip())
        return rx, tx
    except:
        return 0.0, 0.0

def get_docker_stats():
    try:
        result = subprocess.run(
            ["docker", "stats", "--no-stream", "--format", "{{json .}}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )
        lines = result.stdout.strip().split("\n")
        stats = [json.loads(line) for line in lines]
        return stats
    except subprocess.CalledProcessError as e:
        print(f"Error: {e.stderr.strip()}")
        sys.exit(1)

def accumulate_sample(aggregate, stats):
    for s in stats:
        name = s.get("Name", "<unknown>")
        cpu = parse_cpu(s.get("CPUPerc", "0%"))
        mem = parse_mem(s.get("MemUsage", "0B / 0B"))
        mem_perc = parse_cpu(s.get("MemPerc", "0%"))
        net_rx, net_tx = parse_io(s.get("NetIO", "0B / 0B"))
        blk_r, blk_w = parse_io(s.get("BlockIO", "0B / 0B"))

        if name not in aggregate:
            aggregate[name] = {
                "cpu": 0.0,
                "mem": 0.0,
                "mem_perc": 0.0,
                "net_rx": 0.0,
                "net_tx": 0.0,
                "blk_r": 0.0,
                "blk_w": 0.0,
                "samples": 0
            }

        agg = aggregate[name]
        agg["cpu"] += cpu
        agg["mem"] += mem
        agg["mem_perc"] += mem_perc
        agg["net_rx"] += net_rx
        agg["net_tx"] += net_tx
        agg["blk_r"] += blk_r
        agg["blk_w"] += blk_w
        agg["samples"] += 1

def display_averages(aggregate):
    headers = [
        "Container", "CPU (%)", "MEM (MiB)", "MEM %", "Net RX (MB)",
        "Net TX (MB)", "Block R (MB)", "Block W (MB)"
    ]
    print(f"{headers[0]:<18} {headers[1]:>8} {headers[2]:>11} {headers[3]:>8} "
          f"{headers[4]:>13} {headers[5]:>13} {headers[6]:>14} {headers[7]:>14}")
    print("-" * 100)
    for name, data in aggregate.items():
        s = data["samples"]
        print(f"{name:<18} {data['cpu']/s:8.2f} {data['mem']/s:11.2f} {data['mem_perc']/s:8.2f} "
              f"{data['net_rx']/s:13.2f} {data['net_tx']/s:13.2f} {data['blk_r']/s:14.2f} {data['blk_w']/s:14.2f}")

def main():
    parser = argparse.ArgumentParser(description="Docker container metrics monitor with averaging.")
    parser.add_argument("--duration", type=int, default=0, help="Total duration to sample (seconds)")
    parser.add_argument("--sample", type=int, default=0, help="Interval between samples (seconds)")
    args = parser.parse_args()

    check_docker()
    aggregate = {}

    if args.duration > 0 and args.sample > 0:
        end_time = time.time() + args.duration
        while time.time() < end_time:
            stats = get_docker_stats()
            accumulate_sample(aggregate, stats)
            time.sleep(args.sample)
        display_averages(aggregate)
    else:
        stats = get_docker_stats()
        accumulate_sample(aggregate, stats)
        display_averages(aggregate)

if __name__ == "__main__":
    main()
