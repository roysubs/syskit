# `disk-spin-down-policy.sh` - Disk Health & Power Manager

This utility provides a deep-dive audit of your storage hardware and allows you to apply intelligent power-management policies to extend the life of your mechanical drives.

---

## 🔍 Understanding the Audit Output

When run without switches, the script performs a "SMART Audit." Here is what the numbers mean for your drive's health:

### 1. The "Zero Tolerance" Metrics
These should *always* be **0**. Any non-zero value indicates physical media degradation.
*   **Reallocated Sectors**: The number of "bad patches" the drive found and moved to a spare area. 
*   **Pending Sectors**: "Weak" sectors that the drive is watching. These often turn into reallocated sectors later.
*   **Offline Uncorrectable**: Severe errors that the drive couldn't fix even with its internal ECC.

### 2. The "Mechanical Wear" Metrics
These values go up naturally over time, but "high" values tell a story about the drive's past life.
*   **Start/Stop Count (Spin Cycles)**: How many times the motor has started the platters. 
    *   *Note*: Many drives use a 16-bit counter that caps at **65,535**. If you see this exact number, it means the drive has been thrashed by aggressive power settings (common in default Windows "Balanced" modes).
*   **Load Cycle Count**: How many times the head arm has moved into the "parking" zone. 
    *   *Health Limit*: Most modern drives are rated for **300,000 to 600,000** cycles. If you are over 200,000, you are in the "senior" stage of the drive's life.
*   **Power-On Hours**: Total time the drive has been spinning. 
    *   *Comparison*: 9,000h = ~1 year. 70,000h = ~8 years.

---

## 🛠️ Policy Modes

### `--low` (30-Minute Spin-Down)
This policy operates at the **Hardware Level** using the `hdparm` utility.
*   **What it does**: Sets the drive's internal timer to spin down the motor after 30 minutes of no I/O.
*   **The Benefit**: Saves electricity and reduces heat when you aren't using the server.
*   **The APM Tweak**: Sets Advanced Power Management to level 127, which tells the drive firmware it is allowed to spin down to save power.

### `--healer` (Recommended for Server Health)
This is a **System-Wide Optimization** that makes the Linux OS "gentler" on your hardware.
*   **Kernel Writeback Caching**: Sets `vm.dirty_writeback_centisecs` to 60 seconds.
    *   *Why?*: Instead of the disk waking up every 5 seconds for a tiny log update, Linux holds small writes in RAM for 60 seconds. This allows the drive to stay in "Standby" for much longer uninterrupted blocks.
*   **BFQ I/O Scheduler**: Switches mechanical drives to the **Budget Fair Queuing** scheduler.
    *   *Why?*: Standard schedulers can be "jerky" with headers. BFQ optimizes the "mechanical swing" of the arm to reduce physical stress during heavy reads/writes.
*   **Gentle 1-Hour Timer**: Sets a longer 60-minute hardware spin-down. For older drives with high spin-counts, it is better to stay spinning for an extra 30 minutes than to risk a "cold start" every few minutes.

---

## 🤖 AI Analysis Prompt

If you want an AI to give you a custom recommendation for your specific hardware mix, copy the output of the script and use the following prompt:

> "I am running a Linux server on an [HP Microserver N36L]. Here is the SMART output for my drives. Based on the **Power-On Hours**, **Load Cycle Count**, and **Start/Stop Count** for each specific model, which drives should I prioritize for a 'No Spin-down' policy versus an 'Aggressive Spin-down' policy? Are any of these drives approaching their mechanical end-of-life? 
> 
> [PASTE OUTPUT HERE]"

---

## ⚠️ Important Note on Syncthing/Docker
If your Syncthing Database or Docker logs are stored on a mechanical drive, the drive will **never** stay asleep. For maximum "Healer" effectiveness, always keep your active application data/databases on an **SSD** and use the big mechanical drives only for bulk file storage.
