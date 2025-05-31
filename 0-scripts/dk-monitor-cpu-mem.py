#!/usr/bin/env python3
# Author: Roy Wiseman 2025-03
import subprocess
import json
import shutil
import sys
import re

def check_docker():
    if not shutil.which("docker"):
        print("Docker is not installed or not in your PATH.")
        sys.exit(1)

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

def display_stats(stats):
    print(f"{'CONTAINER':<20} {'CPU (%)':>8} {'MEM (MiB)':>10} {'MEM %':>8}")
    print("-" * 50)
    for s in stats:
        cpu = parse_cpu(s.get("CPUPerc", "0%"))
        mem = parse_mem(s.get("MemUsage", "0B / 0B"))
        mem_perc = parse_cpu(s.get("MemPerc", "0%"))
        print(f"{s.get('Name','<unknown>'):<20} {cpu:>8.2f} {mem:>10.2f} {mem_perc:>8.2f}")

if __name__ == "__main__":
    check_docker()
    stats = get_docker_stats()
    display_stats(stats)

