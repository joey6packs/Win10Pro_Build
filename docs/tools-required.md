# Tools Required

All tools listed here must be installed on the build workstation before starting the image creation process.

---

## Windows Assessment and Deployment Kit (Windows ADK)

**Purpose:** Provides DISM, Windows SIM, and oscdimg.

- Download: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
- Required components:
  - Deployment Tools (includes DISM, oscdimg, BCDBoot)
  - Windows System Image Manager (Windows SIM)
- Install the **WinPE add-on** separately if WinPE customization is needed.

> Match the ADK version to the target OS. For Windows 10 22H2, use the ADK for Windows 10, version 2004 or later.

---

## DISM (Deployment Image Servicing and Management)

Included with Windows ADK and also built into Windows 10/11.

Used for:
- Mounting the WIM/ISO
- Integrating cumulative updates (`.msu` / `.cab`)
- Adding/removing Windows features
- Injecting drivers

---

## oscdimg

Included with Windows ADK (Deployment Tools component).

Used to repackage the modified install files back into a bootable `.iso`.

---

## Windows System Image Manager (Windows SIM)

Included with Windows ADK.

Used to create and validate `autounattend.xml` answer files against the Windows catalog (`.clg`).

---

## Source Media

- Windows 10 Pro 22H2 ISO (Build 19045.3803 or later)
- Obtain via: [Microsoft Media Creation Tool](https://www.microsoft.com/en-us/software-download/windows10) or VLSC

---

## Cumulative Updates

Download from the Microsoft Update Catalog:
https://www.catalog.update.microsoft.com/Search.aspx?q=windows%2010%20cumulative%2022H2

Recommended download format: **`.msu`** (standalone update package)

---

## Optional Tools

| Tool | Purpose |
|---|---|
| 7-Zip | Extract ISO contents without mounting |
| NTLite | GUI-based image editing (alternative to DISM CLI) |
| PowerShell 5.1+ | Running post-install scripts |
| Rufus | Writing the final ISO to USB for bare-metal boot |
