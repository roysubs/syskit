# `preserve-cpu-policy.sh` - CPU Health & Power Manager

This utility allows you to monitor and control the power states of your CPU. It is designed to maximize efficiency without sacrificing the responsiveness required for network services like Syncthing or SSH.

---

## 🔍 Understanding the CPU Audit

Running the script without switches provides a snapshot of your current CPU behavior:

### 1. Governors (The "Brain")
The governor decides how quickly the CPU should "clock up" when work arrives.
*   **Powersave**: Locks the CPU to its lowest possible speed. Best for absolute minimum heat.
*   **Ondemand / Conservative**: The CPU stays low at idle but "ramps up" when you start a task. Optimal for a reactive server.
*   **Performance**: Locks the CPU at its maximum speed. High waste for a home server.

### 2. C-States (The "Deep Nap")
C-States are the idle sleep modes of the processor.
*   **C0**: Fully active and working.
*   **C1-C6/C7**: Successively deeper sleep states. The deeper the state, the less power used, but the tiny fraction of a millisecond it takes to "wake up" increases slightly.
*   *Note*: Modern CPUs (even in the Microserver) are incredibly fast at this. Deep C-states are "free" energy savings that do NOT affect network reactivity.

---

## 🛠️ Policy Modes

### `--low` (Maximum Savings)
*   **What it does**: Forces the `powersave` governor.
*   **The Benefit**: Minimum possible power draw. Perfect if the server is mostly idle and you don't mind a slight "sluggishness" during heavy file indexing.

### `--healer` (Recommended for Servers)
This is the "Pro" balance for a stable home server.
*   **Conservative Governor**: It uses a "step-up" approach to frequency. It won't jump to max speed for a tiny background task, preventing unnecessary heat spikes.
*   **Powertop Auto-Tune**: This is the "secret sauce." It optimizes the power draw of the motherboard components (PCIe lanes, SATA controllers, USB ports) that are often left in "High Performance" state by default.
*   **Responsiveness**: The system remains 100% responsive to the network.

### `--default`
*   Resets the system to standard Linux behavior, allowing the OS to manage frequency based on its default balanced profiles.

---

## 🤖 AI Analysis Prompt

To get a custom optimization plan for your specific CPU architecture, run the audit and paste it into an AI with this prompt:

> "I am running a Linux server on an [HP Microserver N36L]. Here is the output of my CPU power audit. Based on the available **C-States** and the **Frequency Range**, how should I tune my `conservative` governor for the best balance between power savings and Syncthing sync speed? Are there any specific kernel parameters I should add to my boot config to enable deeper idle states?"

---

## 💡 Pro Tip: Network Reactivity
A common fear is that "Low Power" means the server won't hear a request. On Linux, this is **not true**. Even in its deepest `powersave` mode, the CPU is still "listening" at the hardware level. A network packet will trigger a hardware interrupt that wakes the CPU instantly.
