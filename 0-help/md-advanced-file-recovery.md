# Advanced Forensic and Data Recovery Tools for Filename Discovery

This list provides information on tools that may assist in discovering filenames on corrupted partitions where tools like PhotoRec and TestDisk have not succeeded. Focus is on filename and directory structure recovery.

## Commercial Forensic Suites

These are powerful, often court-validated tools, typically with high costs and requiring professional licensing or training.

- EnCase Forensic:
  - Platform: Windows
  - Interface: GUI
  - Supports ext4: Yes (generally through various plugins or modules, Linux OS support for acquisition)
  - Supports NTFS: Yes (core strength)
  - Estimated Price: $3,500 - $5,000+ per license, often requires training. Quote-based.

- X-Ways Forensics:
  - Platform: Windows
  - Interface: GUI (known for being very information-dense)
  - Supports ext4: Yes (native support)
  - Supports NTFS: Yes (native, very detailed support)
  - Estimated Price: Approx. $1,500 - $3,500 (licenses vary, e.g., perpetual, annual updates)

- Magnet AXIOM:
  - Platform: Windows (for the main application)
  - Interface: GUI
  - Supports ext4: Yes
  - Supports NTFS: Yes
  - Estimated Price: $3,000 - $5,000+ per year, often quote-based for agency/enterprise.

- FTK (Forensic Toolkit) by Exterro:
  - Platform: Windows
  - Interface: GUI
  - Supports ext4: Yes
  - Supports NTFS: Yes
  - Estimated Price: $3,000 - $5,000+, quote-based, often involves training packages.

## Advanced Data Recovery Software (often with Forensic Capabilities)

These tools are generally more accessible in terms of price and are widely used by data recovery professionals. Many can work on disk images.

- R-Studio:
  - Platform: Windows, macOS, Linux
  - Interface: GUI
  - Supports ext4: Yes
  - Supports NTFS: Yes
  - Estimated Price: Free demo (limited recovery size). Licenses range from approx. $50 (NTFS/FAT only) to $80 (Standard, multi-filesystem), $180 (Network edition). Technician licenses are higher (approx. $300-$900).

- DMDE (DM Disk Editor and Data Recovery Software):
  - Platform: Windows, macOS, Linux, DOS
  - Interface: GUI (technical) and Console (for some versions/tasks)
  - Supports ext4: Yes
  - Supports NTFS: Yes
  - Estimated Price: Free version (recover up to 4000 files from one folder). Paid licenses: Express (approx. $20/year), Standard (approx. $48 perpetual for 1 OS), Professional (approx. $95-$133 perpetual, multi-OS option).

- DiskGenius:
  - Platform: Windows
  - Interface: GUI
  - Supports ext4: Yes (read/write and recovery, Professional Edition needed for recovery)
  - Supports NTFS: Yes
  - Estimated Price: Free version (limited recovery, e.g., small files). Standard (approx. $70), Professional (approx. $100, needed for ext4 recovery).

- UFS Explorer:
  - Platform: Windows, macOS, Linux
  - Interface: GUI
  - Supports ext4: Yes
  - Supports NTFS: Yes
  - Estimated Price: Standard Recovery (approx. €60), Professional Recovery (approx. €600), RAID Recovery (approx. €150). Specific versions for specific filesystems also exist (e.g., Raise Data Recovery for NTFS, etc., usually cheaper).

- ReclaiMe Pro:
  - Platform: Windows (can recover data from macOS and Linux formatted drives connected to a Windows PC)
  - Interface: GUI
  - Supports ext4: Yes (Ultimate version)
  - Supports NTFS: Yes
  - Estimated Price: Standard (approx. $90, Windows FS), Ultimate (approx. $190, adds macOS/Linux FS). Pro version (for data recovery businesses) approx. $800/year.

## Open Source Forensic Platforms

These are free and open-source, often requiring a deeper understanding of filesystem structures.

- The Sleuth Kit (TSK):
  - Platform: Windows, Linux, macOS (primarily command-line)
  - Interface: Console (command-line tools)
  - Supports ext4: Yes
  - Supports NTFS: Yes
  - Estimated Price: Free (Open Source)

- Autopsy (GUI for The Sleuth Kit):
  - Platform: Windows, Linux, macOS
  - Interface: GUI
  - Supports ext4: Yes (via The Sleuth Kit)
  - Supports NTFS: Yes (via The Sleuth Kit)
  - Estimated Price: Free (Open Source). Commercial training and support are available. Some vendors might sell pre-configured versions on media (e.g., USB/CD as found in one search result for $10-$20, but the software itself is free from the official site).

---
Important Notes:
-   **Prices are estimates:** Software pricing can change frequently and may vary by region, license type (personal, professional, technician, perpetual, subscription), and current promotions. Always check the official vendor websites for the most up-to-date information. "Quote-based" means you need to contact the vendor for pricing.
-   **Work on an Image:** Always create a byte-for-byte disk image of the corrupted partition/disk before attempting any recovery. Work on the image, not the original drive. Tools like `ddrescue` (Linux, free) are recommended for creating images, especially from potentially failing drives.
-   **Filesystem Knowledge:** Deeper understanding of how ext4 and NTFS store metadata (inodes, MFT, directory entries) can be beneficial, especially when using command-line tools or analyzing raw data.
-   **Severity of Corruption:** The ability to recover filenames is highly dependent on the extent and type of corruption. If the metadata structures holding filename and directory information are severely damaged or overwritten, recovery might be impossible even with these advanced tools.
