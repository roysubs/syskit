# Gaming Emulators Overview

This document provides an overview of gaming emulators, with a focus on those that can run in a container with a web front-end, and specific attention to ZX Spectrum and BBC Micro emulation. The information reflects the landscape as of May 2025.

## The Emulator Landscape: A Broad View

General-purpose emulator front-ends and distributions:

* **RetroPie**
    * Description: A collection of emulators and front-ends (primarily EmulationStation) built on Linux (usually Raspberry Pi OS). Highly configurable, supports many systems.
    * Containerization/Web UI: Not designed for containerized web access out-of-the-box, but its components (like RetroArch) can be part of such solutions.
    * Status: Actively developed and supported by a large community. (Status: May 2025)

* **Batocera.linux**
    * Description: A free, open-source, standalone retro gaming OS. Easy to use, broad hardware support.
    * Containerization/Web UI: More of a dedicated OS. Underlying emulators are common.
    * Status: Actively developed with regular updates. (Status: May 2025)

* **Lakka**
    * Description: Lightweight Linux distribution transforming a small computer into a retro gaming console. Official OS of RetroArch.
    * Containerization/Web UI: Designed as a barebones OS for direct hardware use.
    * Status: Actively maintained. (Status: May 2025)

* **RetroArch**
    * Description: A front-end for various emulator "cores" (individual emulators packaged as libraries). Versatile, multi-platform, features like shaders, netplay, rewinding.
    * Containerization/Web UI: Core of many web-based solutions (e.g., EmulatorJS). Some builds have web server capabilities.
    * Status: Very actively developed with frequent updates. (Status: May 2025)

## Emulators with Web Front-Ends (Like EmulatorJS)

Focusing on solutions similar to the `linuxserver.io/emulatorjs` container:

* **EmulatorJS (and `linuxserver.io` container)**
    * How it works: Uses Emscripten to compile Libretro cores (from RetroArch) into JavaScript/WebAssembly for browser execution. The `linuxserver.io` container bundles this with a web server and management tools.
    * ZX Spectrum & BBC Micro Support:
        * ZX Spectrum: Generally supported via RetroArch cores like Fuse or FBNeo. Check the `linuxserver.io` container documentation or the EmulatorJS GitHub repository for specific included cores. (Ongoing system support expansion in the `linuxserver.io` version is typical).
        * BBC Micro: Support in browser-based RetroArch cores is less common. The MAME core in RetroArch *can* emulate BBC Micro, but its performance and compatibility in a WebAssembly environment might vary. You would need to check the specific cores included with your EmulatorJS setup.
    * Status: Both the EmulatorJS library itself and the `linuxserver.io` container are actively maintained. The `linuxserver.io` container sees regular updates for its base image and EmulatorJS components. (Status: May 2025)

* **Other Potential Web Front-End Solutions**
    * **Afterplay.io**: A commercial platform offering browser-based retro gaming. Lists ZX Spectrum. Not a self-hosted container solution. (Status: Appears active as of May 2025).
    * **Custom RetroArch Web Player/Deployments**: A more DIY approach to build or find other web front-ends that serve RetroArch cores compiled to WebAssembly.
    * **Jsbeeb**: Specifically for the BBC Micro, jsbeeb is a JavaScript-based emulator that runs directly in the browser, developed by Matt Godbolt. It can load disk images locally or from cloud storage.
        * Status: Actively maintained (source code on GitHub). (Status: May 2025)
    * **zxplay/zxplay (GitHub)**: A mobile-friendly ZX Spectrum emulator for the browser, running emulation in a Web Worker. The project is on GitHub.
        * Status: Check its GitHub repository for the most current maintenance status. (Status: Project exists as of May 2025)
    * **Self-hosting Generic Web Servers with Individual Emulators**: For systems like ZX Spectrum or BBC Micro, individual emulators written in JavaScript or compilable to WebAssembly could be hosted. This would lack the unified interface of EmulatorJS.

## ZX Spectrum and BBC Micro Emulation Landscape

### ZX Spectrum Emulators

* **Standalone Desktop Emulators (often the most feature-rich and accurate):**
    * **Fuse (Free Unix Spectrum Emulator)**: Highly accurate, open-source, and available on many platforms. It's often a core used in multi-system emulators like RetroArch.
        * Status: Actively maintained. (Status: May 2025)
    * **ZEsarUX**: A very comprehensive ZX Spectrum and Sinclair family emulator, known for its accuracy and debugging features.
        * Status: Actively maintained. (Status: May 2025)
    * **Speccy**: Popular Android emulator for the ZX Spectrum family. (Check Google Play Store for latest updates).
    * **Spectaculator**: A long-standing commercial emulator, particularly for Windows and iOS. (Check their website for updates).

* **Web-Based ZX Spectrum Emulators:**
    * **RetroArch cores (e.g., Fuse, FBNeo) via EmulatorJS**: A strong contender for a containerized web solution.
    * **zxplay**: Dedicated browser-based ZX Spectrum emulator (found on GitHub).
    * **Spectral**: A ZX Spectrum emulator with a focus on CRT screen imitation effects, with a GitHub repository. (Check GitHub for status).

### BBC Micro Emulators

* **Standalone Desktop Emulators:**
    * **BeebEm**: One of the oldest and most well-known BBC Micro emulators for Windows and other platforms. It is quite mature.
        * Status: Development has been slower in recent years, but it's a stable emulator. Check its official site for the latest. (Status: May 2025)
    * **B-em**: Another excellent and accurate BBC Micro emulator. Sarah Walker, its author, open-sourced the code, which formed the basis for jsbeeb.
        * Status: Appears to be mature and stable. The open-sourcing has allowed its legacy to continue. (Status: May 2025)
    * **MAME (Multiple Arcade Machine Emulator)**: While known for arcade games, MAME also emulates a vast number of computer systems, including the BBC Micro, with a focus on accuracy.
        * Status: Very actively developed. Its BBC Micro driver is maintained as part of the overall MAME project. (Status: May 2025)

* **Web-Based BBC Micro Emulators:**
    * **jsbeeb**: A leading choice for BBC Micro emulation directly in a web browser (e.g., jsbeeb.com or bbc.xania.org). It's accessible and well-regarded.
        * Status: Actively maintained. (Status: May 2025)
    * **BBC Micro Emulator (clp.bbcrewind.co.uk)**: This site hosts a collection of BBC Micro software running in a browser emulator, likely using jsbeeb or similar technology, as part of the BBC Computer Literacy Project archive.
    * **RetroArch cores (e.g., MAME) via EmulatorJS**: While MAME supports BBC Micro, its suitability and performance within a web/EmulatorJS context would need verification.

## Key Considerations for Containerized Web Emulation

* **Performance**: Emulation in a browser via WebAssembly can be demanding for complex systems. ZX Spectrum and BBC Micro are less demanding.
* **Core Availability and Quality**: The experience hinges on the quality and compatibility of the underlying Libretro cores if using a RetroArch-based solution.
* **Ease of Use**: A good web front-end should make it easy to browse, launch, and manage games and save states.
* **Server Resources**: The server primarily serves files; the actual emulation happens client-side. Server load is mostly about concurrent users accessing the library.
* **ROM Management**: Setting up and scanning ROMs is a key part of the process. The `linuxserver.io` container for EmulatorJS provides tools for this.

## Staying Up-to-Date

* **GitHub Repositories**: For open-source emulators and front-ends (EmulatorJS, RetroArch, Fuse, jsbeeb, zxplay, etc.), the "commits" or "releases" section is the best place to check for recent activity.
* **Official Websites/Forums**: Many emulators have official sites with news sections or community forums where updates are announced.
* **LinuxServer.io Announcements**: For their containers, LinuxServer.io has a blog and Discord server for update announcements.
* **Emulation News Sites**: Websites dedicated to emulation news (e.g., RetroRGB, EmuCR) often report on significant updates.

## Summary and Recommendations

Given your interest in a containerized web front-end and fondness for ZX Spectrum and BBC Micro:

1.  **Continue with `linuxserver.io/emulatorjs`**: This is an excellent, actively maintained solution.
    * **For ZX Spectrum**: It's highly likely to work well out-of-the-box using one of its RetroArch cores.
    * **For BBC Micro**: Investigate which cores are available in your EmulatorJS instance. If a direct Libretro core for BBC Micro (like a specific version of MAME compiled for WebAssembly) is present and performs well, that's your integrated solution.

2.  **Explore `jsbeeb` for a dedicated BBC Micro Web Experience**: If BBC Micro support in EmulatorJS is lacking or not as polished, `jsbeeb` (jsbeeb.com) is a fantastic, dedicated browser-based emulator. While not integrated into the EmulatorJS interface, it's a direct way to play BBC Micro games in a browser.
    * Status: Actively maintained. (Status: May 2025)

3.  **Look into `zxplay` for an alternative ZX Spectrum Web Experience**: Similar to jsbeeb for BBC Micro, `zxplay` (on GitHub) offers a focused web emulation experience for the ZX Spectrum.
    * Status: Check GitHub for current activity. (Status: May 2025)

4.  **Keep an eye on RetroArch Web Developments**: As the core technology behind EmulatorJS, advancements in RetroArch's web capabilities (new cores, better performance) will likely filter down.

The landscape is broad, but your current `linuxserver.io` setup is a very strong base. For your specific beloved 8-bit systems, dedicated web emulators like jsbeeb and zxplay are excellent supplementary options if the integrated experience within EmulatorJS needs a boost for those particular machines. Most of the key projects mentioned (RetroArch, EmulatorJS, jsbeeb, Fuse, MAME) are actively maintained as of May 2025.
