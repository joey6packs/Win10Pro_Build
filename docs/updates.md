# Windows Updates

Tracking all updates integrated into the image, with download sources and integration status.

---

## Current Target Build

| Item | Value |
|---|---|
| Base ISO Build | 19045.3803 |
| Last Confirmed Working (offline) | 19045.6216 + SSU-6935 (KB5075912) |
| Target Build | 19045.7058 (KB5078885 — integration under investigation) |
| Last Updated | 2026-03-29 |

---

## Update Strategy

The base ISO (19045.3803, Dec 2023) requires a chain of bridge updates to advance the
servicing stack before the March 2026 CU can be applied offline.

| Step | KB | Method | Build After | Status |
|---|---|---|---|---|
| 1 | KB5039299 (Jun 2024) | DISM offline — SSU+CU CAB, session-isolated | 19045.4598 | Confirmed working |
| 2 | KB5050081 (Jan 2025) | DISM offline — SSU+CU CAB, session-isolated | 19045.5440 | Confirmed working |
| 3 | KB5063709 (Aug 2025) | DISM offline — SSU+CU CAB, session-isolated | 19045.6216 | Confirmed working |
| 4 | KB5075912 (Feb 2026) | DISM offline — SSU CAB only (CU intentionally skipped) | SSU-6935 applied; OS UBR stays 6216 | Confirmed working |
| 5 | KB5078885 (Mar 2026) | Under investigation — see KB5078885 section | 19045.7058 | Setup fails from ISO |

**Session isolation:** each SSU and CU CAB is applied in a separate DISM mount/commit
session to prevent CBS component store corruption (errors 14099, 0x800f0830).

---

## Integrated Updates

### KB5039299 — 2024-06 Cumulative Update Preview (bridge 1)

| Field | Value |
|---|---|
| Full Title | 2024-06 Cumulative Update Preview for Windows 10 Version 22H2 for x64-based Systems |
| Type | Cumulative Update Preview (optional/non-security) |
| Release Date | 2024-06-25 |
| OS Build After | 19045.4598 |
| Catalog URL | https://www.catalog.update.microsoft.com/Search.aspx?q=KB5039299 |
| Purpose | Advances servicing stack from 3803 base to a level compatible with later CUs |
| Note | Most 2024 Patch Tuesday CUs (KB5044273, KB5043064, etc.) have been pulled from the catalog as superseded. KB5039299 is the latest 2024 update still available for direct download. |

**Integration command:**
```powershell
dism /Image:"V:\Lab\Mount" /Add-Package `
     /PackagePath:"V:\Lab\ISOs\Win10\Updates\windows10.0-kb5039299-x64.msu" `
     /ScratchDir:"V:\Lab\Scratch"
```

---

### KB5050081 — 2025-01 Cumulative Update Preview (bridge 2)

| Field | Value |
|---|---|
| Full Title | 2025-01 Cumulative Update Preview for Windows 10 Version 22H2 for x64-based Systems |
| Type | Cumulative Update Preview (optional/non-security) |
| Release Date | 2025-01-28 |
| OS Build After | 19045.5440 |
| Catalog URL | https://www.catalog.update.microsoft.com/Search.aspx?q=KB5050081 |
| Purpose | Bridge 2: advances servicing stack from 4598 level into mid-2025 range |

---

### KB5063709 — 2025-08 Cumulative Update (bridge 3)

| Field | Value |
|---|---|
| Full Title | 2025-08 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems |
| Type | Cumulative Update (LCU) |
| Release Date | 2025-08-12 |
| OS Build After | 19045.6216 |
| Catalog URL | https://www.catalog.update.microsoft.com/Search.aspx?q=KB5063709 |
| Purpose | Bridge 3: advances servicing stack from 5440 into Aug 2025 range; final confirmed clean offline step |

---

### KB5075912 — 2026-02 Cumulative Update (SSU only applied)

| Field | Value |
|---|---|
| Full Title | 2026-02 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems |
| Type | Cumulative Update (LCU) |
| Release Date | 2026-02-10 |
| OS Build After | 19045.6937 (CU); SSU-19041.6935 (SSU component only) |
| Catalog URL | https://www.catalog.update.microsoft.com/Search.aspx?q=KB5075912 |
| Purpose | Apply SSU-6935 to advance servicing stack before KB5078885 |

**Important — CU intentionally skipped:**
Applying the KB5075912 CU CAB offline triggers CBS error 14099
(`CBS_E_ARRAY_ELEMENT_MISSING`) which permanently corrupts the component store
(`0x800f0830` on all subsequent packages). Only the SSU CAB is applied. The CU content
is superseded by KB5078885 anyway.

The SSU does not change the OS UBR — `winver` will still show 19045.6216 after this step.

**boot.wim:** SSU-6935 is also applied to boot.wim index 2 (WinPE setup environment) to
resolve a version mismatch when setup.exe from a 3803-era WinPE tries to install a
7058-level image.

---

### KB5078885 — 2026-03 Cumulative Update (investigation ongoing)

| Field | Value |
|---|---|
| Full Title | 2026-03 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems |
| Type | Cumulative Update (LCU) — ESU |
| Release Date | 2026-03-10 |
| OS Build After | 19045.7058 |
| File Size (x64) | ~846 MB |
| Catalog URL | https://www.catalog.update.microsoft.com/Search.aspx?q=KB5078885 |
| Support Article | https://support.microsoft.com/en-us/topic/march-10-2026-kb5078885-os-builds-19045-7058-and-19044-7058-5738282d-0b7f-426e-a42b-bd7698ab6dbb |

**Key fixes / changes:**
- GPU stability fix affecting system stability
- Updated Secure Boot 2023 certificates (older certificates expire June 2026)
- Addresses 78 CVEs (March 2026 Patch Tuesday)
- ESU update — requires ESU enrollment for Windows Update delivery; MSU installs locally

**Known offline integration issue:**
DISM offline apply of KB5078885 (both MSU direct and CAB extraction paths) exits with
error 14099 (`CBS_E_ARRAY_ELEMENT_MISSING`). The OS binaries reach build 7058
(ntoskrnl.exe verified) but CBS metadata is inconsistent. WIM export does not resolve
this. Setup.exe detects the inconsistency and aborts with "Setup cannot continue due
to a corrupted installation file."

CAB extraction path additionally triggers `0x80073713` (`ERROR_ADVANCED_INSTALLER_FAILED`)
when the embedded SSU (KB5081263/SSU-7052) conflicts with the already-applied SSU-6935.

**Remediation paths under investigation:**

| Option | Approach | Script |
|---|---|---|
| Option 1 | Install from 6935 ISO → apply KB5078885 online → sysprep → capture WIM | Manual |
| Option 2 | Apply KB5078885 directly after 6216, no KB5075912 SSU pre-step | `Step3-BuildIncrementalISOs.ps1 -TargetBuild 7058direct` |

---

## Update Integration Order

When multiple updates are present, always apply in this order:

1. **Servicing Stack Update (SSU)** — in its own DISM mount/commit session
2. **Cumulative Update (LCU)** — in a separate mount/commit session
3. **Out-of-band / optional updates** — as needed

Session isolation (unmount/commit/remount between SSU and CU) is required to prevent
CBS component store corruption.

---

## Verifying Integration

After unmounting the image, confirm the build number via the offline registry:

```powershell
reg load HKLM\OFFLINE "V:\Lab\Mount\Windows\System32\config\SOFTWARE"
$ubr   = (Get-ItemProperty 'HKLM:\OFFLINE\Microsoft\Windows NT\CurrentVersion').UBR
$build = (Get-ItemProperty 'HKLM:\OFFLINE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
reg unload HKLM\OFFLINE
Write-Host "Build: $build.$ubr"
```

The `UBR` value should be **7058** after KB5078885 is successfully applied.

---

## Future Updates

When a new monthly CU is released:
1. Download from the [Microsoft Update Catalog](https://www.catalog.update.microsoft.com/Search.aspx?q=windows%2010%20cumulative%2022H2)
2. Add a new entry to this file and to [changelog.md](changelog.md)
3. Increment the build tag in `changelog.md`
