# Win10Pro_Build

Custom Windows 10 Professional 22H2 image with slipstreamed cumulative updates and pre-installed applications.

| Item | Value |
|---|---|
| Base OS | Windows 10 Pro 22H2 |
| Base Build | 19045.3803 |
| Current Build (final) | 19045.6216 |
| Bridge CU 1 | KB5039299 (2024-06-25) → 19045.4598 (offline) |
| Bridge CU 2 | KB5050081 (2025-01-28) → 19045.5440 (offline) |
| Bridge CU 3 | KB5063709 (2025-08-12) → 19045.6216 (offline) |
| KB5078885 (Mar 2026) | Blocked — ESU licensing required (see docs/updates.md) |
| Architecture | x64 |
| Update Channel | General Availability |

---

## Overview

This project documents the process of creating a deployable Windows 10 Pro 22H2 ISO with:

- Latest cumulative updates integrated (slipstreamed via DISM)
- Selected applications pre-installed
- Automated setup via `autounattend.xml`
- Post-install configuration scripts

The resulting image can be used for bare-metal deployments or virtual machine provisioning.

---

## Repository Structure

```
Win10Pro_Build/
├── autounattend/       # Unattended answer files (Windows SIM)
├── configs/            # App and system configuration files
├── docs/               # Step-by-step build documentation
│   ├── build-process.md
│   ├── tools-required.md
│   └── changelog.md
└── scripts/            # PowerShell / batch scripts for post-install tasks
```

---

## Prerequisites

See [docs/tools-required.md](docs/tools-required.md) for the full list of tools needed before starting the build.

---

## Build Process

See [docs/build-process.md](docs/build-process.md) for the complete step-by-step workflow.

---

## Updates

Cumulative updates are sourced from the Microsoft Update Catalog:
https://www.catalog.update.microsoft.com/Search.aspx?q=windows%2010%20cumulative%2022H2

See [docs/updates.md](docs/updates.md) for per-KB download info and integration commands.
See [docs/changelog.md](docs/changelog.md) for a log of updates integrated into each build revision.

---

## Notes

- Large binary files (`.iso`, `.exe`, `.msi`, `.wim`) are excluded via `.gitignore`.
- This repo tracks scripts, answer files, configs, and documentation only — not the image binaries themselves.
