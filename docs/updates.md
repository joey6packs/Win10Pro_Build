# Windows Updates

Tracking all updates integrated into the image, with download sources and integration status.

---

## Current Target Build

| Item | Value |
|---|---|
| Base ISO Build | 19045.3803 |
| Offline Build (WIM) | 19045.5440 |
| Final Installed Build | 19045.7058 (after first-logon KB5078885) |
| Last Updated | 2026-03-28 |

---

## Update Strategy Note

The base ISO (19045.3803, Dec 2023) has a servicing stack too old to accept the March 2026 CU directly. Additionally, the ESU-era SSU (7052) bundled in KB5078885 requires full boot context and cannot be applied by DISM offline.

**Strategy: offline bridges to 19045.5440, then KB5078885 on first logon.**

| Step | KB | Method | Result |
|---|---|---|---|
| 1 | KB5039299 (Jun 2024 preview) | DISM offline (CAB extraction) | 19045.3803 → 19045.4598 |
| 2 | KB5050081 (Jan 2025 preview) | DISM offline (CAB extraction) | 19045.4598 → 19045.5440 |
| 3 | KB5078885 (Mar 2026) | `wusa.exe` via `FirstLogonCommands` | 19045.5440 → 19045.7058 |

KB5075912 (Feb 2026, bridge 3) was attempted offline — SSU CAB applied but CU CAB fails with error 14099. Skipped; KB5078885 can be installed directly from 5440 via online wusa.

> Most 2024 Patch Tuesday CUs (KB5044273, KB5043064, KB5040427, etc.) have been pulled from
> the Microsoft Update Catalog as superseded. KB5039299 is the most recent 2024 build still
> available for direct download.

---

## Integrated Updates

### KB5039299 — 2024-06 Cumulative Update Preview (bridge)

| Field | Value |
|---|---|
| Full Title | 2024-06 Cumulative Update Preview for Windows 10 Version 22H2 for x64-based Systems (KB5039299) |
| Type | Cumulative Update Preview (optional/non-security) |
| Release Date | 2024-06-25 |
| OS Build After | 19045.4598 |
| Catalog URL | https://www.catalog.update.microsoft.com/Search.aspx?q=KB5039299 |
| Purpose | Bridge the servicing stack from 19045.3803 base to a level compatible with KB5078885 |
| Note | KB5044273 (Oct 2024) and other 2024 CUs have been pulled from the catalog as superseded. KB5039299 is the most recent 2024 update still available for download. |

**Integration command:**
```powershell
dism /Image:"V:\RWJBH-Lab\Mount" /Add-Package `
     /PackagePath:"V:\RWJBH-Lab\ISOs\Win10\windows10.0-kb5039299-x64.msu" `
     /ScratchDir:"V:\RWJBH-Lab\Scratch"
```

---

### KB5050081 — 2025-01 Cumulative Update Preview (bridge 2)

| Field | Value |
|---|---|
| Full Title | 2025-01 Cumulative Update Preview for Windows 10 Version 22H2 for x64-based Systems (KB5050081) |
| Type | Cumulative Update Preview (optional/non-security) |
| Release Date | 2025-01-28 |
| OS Build After | 19045.5440 |
| Catalog URL | https://www.catalog.update.microsoft.com/Search.aspx?q=KB5050081 |
| Purpose | Bridge 2: advances the SSU from the 4585 level (KB5039299) into mid-2025 range before applying the March 2026 CU |

---

### KB5075912 — 2026-02 Cumulative Update (bridge 3)

| Field | Value |
|---|---|
| Full Title | 2026-02 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems (KB5075912) |
| Type | Cumulative Update (LCU) |
| Release Date | 2026-02-10 |
| OS Build After | 19045.6937 |
| Catalog URL | https://www.catalog.update.microsoft.com/Search.aspx?q=KB5075912 |
| Purpose | Bridge 3: advances the SSU from the KB5050081 level into Feb 2026, one step before the final CU |

---

### KB5078885 — 2026-03 Cumulative Update

| Field | Value |
|---|---|
| Full Title | 2026-03 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems (KB5078885) |
| Type | Cumulative Update (LCU) |
| Release Date | 2026-03-10 |
| OS Build After | 19045.7058 |
| File Size (x64) | ~846 MB |
| SSU Prerequisite | None — SSU bundled in this CU |
| Catalog URL | https://www.catalog.update.microsoft.com/Search.aspx?q=KB5078885 |
| Support Article | https://support.microsoft.com/en-us/topic/march-10-2026-kb5078885-os-builds-19045-7058-and-19044-7058-5738282d-0b7f-426e-a42b-bd7698ab6dbb |

**Key fixes / changes:**
- GPU stability fix affecting system stability
- Includes updated Secure Boot 2023 certificates (older certificates expire June 2026)
- Addresses 78 CVEs (March 2026 Patch Tuesday)

**Download:**
1. Go to the [Microsoft Update Catalog](https://www.catalog.update.microsoft.com/Search.aspx?q=KB5078885)
2. Select: **Windows 10 Version 22H2 for x64-based Systems**
3. Download the `.msu` file

**Integration command:**
```powershell
dism /Image:"C:\WinBuild\Mount" /Add-Package `
     /PackagePath:"C:\WinBuild\Updates\windows10.0-kb5078885-x64.msu" `
     /ScratchDir:"C:\WinBuild\Scratch"
```

---

## Update Integration Order

When multiple updates are present, apply in this order:

1. **Servicing Stack Update (SSU)** — if required separately
2. **Cumulative Update (LCU)** — monthly rollup
3. **Out-of-band / optional updates** — as needed

For this build, only one update is required (KB5078885 includes the SSU).

---

## Verifying Integration

After unmounting the image, confirm the build number:

```powershell
dism /Get-WimInfo /WimFile:"C:\WinBuild\ISO\sources\install.wim" /Index:<Pro_Index>
```

Look for `ServicePack Build` or check the build in the mounted image registry:

```powershell
# While image is mounted:
reg load HKLM\OFFLINE "C:\WinBuild\Mount\Windows\System32\config\SOFTWARE"
reg query "HKLM\OFFLINE\Microsoft\Windows NT\CurrentVersion" /v "UBR"
reg unload HKLM\OFFLINE
```

The `UBR` (Update Build Revision) value should be **7058** after KB5078885 is applied.

---

## Future Updates

When a new monthly CU is released:
1. Download from the [Microsoft Update Catalog](https://www.catalog.update.microsoft.com/Search.aspx?q=windows%2010%20cumulative%2022H2)
2. Add a new entry to this file and to [changelog.md](changelog.md)
3. Increment the build tag in `changelog.md`
