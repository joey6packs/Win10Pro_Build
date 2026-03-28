# autounattend

Answer files for unattended Windows Setup.

---

## Files

| File | Purpose |
|---|---|
| `autounattend.xml` | Primary answer file — placed at the root of the ISO or bootable USB |

---

## How It Works

Windows Setup automatically detects `autounattend.xml` at the root of the installation media and uses it to answer setup prompts without user interaction.

The file is authored with **Windows System Image Manager (Windows SIM)**, part of the Windows ADK.

---

## Key Sections (Configuration Passes)

| Pass | What It Controls |
|---|---|
| `windowsPE` | Disk partitioning, edition selection, product key, regional settings during setup |
| `specialize` | Computer name, network, time zone — runs after first boot before user setup |
| `oobeSystem` | OOBE skip, local account creation, `FirstLogonCommands` for post-install scripts |

---

## Usage

Place `autounattend.xml` at the **root** of the bootable ISO or USB drive before booting. Windows Setup picks it up automatically — no additional flags needed.

---

## Validation

Always validate the answer file against the Windows catalog before building the ISO:

1. Open **Windows SIM**
2. Open the `install.wim` and select the Pro index to generate a catalog (`.clg`)
3. Open `autounattend.xml` in Windows SIM
4. Use **Tools → Validate Answer File** and resolve any errors
