# Changelog

Build revision history for the custom Windows 10 Pro 22H2 image.

---

## Format

Each entry records:
- **Build tag** — version identifier for the output ISO
- **Base build** — source Windows build number
- **Updates integrated** — KB articles slipstreamed
- **Apps added** — applications pre-installed or provisioned
- **Notes** — any known issues or deviations

---

## Revisions

### v0.4 — 2026-03-29

| Field | Value |
|---|---|
| Base Build | 19045.3803 (22H2) |
| Confirmed Working Builds | 19045.3803, 19045.4598, 19045.5440, 19045.6216, 19045.6216+SSU-6935 |
| Target Build | 19045.7058 (investigation ongoing) |
| Updates Offline | KB5039299, KB5050081, KB5063709, KB5075912 (SSU only) |
| Updates Pending | KB5078885 (offline integration blocked — see notes) |
| Apps Added | _(none yet)_ |
| Output ISOs | Win10Pro_22H2_19045.{3803,4598,5440,6216,6935,7058_fresh,7058_direct}.iso |

**Notes:**
- Full incremental ISO set built for each update level to isolate setup failure root cause.
- Builds 3803 through 6935 all confirmed: install completes without errors.
- 19045.6935 ISO shows winver 19045.6216 — expected, SSU does not change the OS UBR.
- 7058_fresh ISO fails with "Setup cannot continue due to a corrupted installation file."
  Root cause: KB5078885 offline apply exits with 14099 (CBS_E_ARRAY_ELEMENT_MISSING),
  leaving the CBS component store in an inconsistent state that setup.exe detects.
- Two remediation paths under investigation:
  - **Option 1**: Install from 6935 ISO → apply KB5078885 online → sysprep → capture WIM.
  - **Option 2**: Apply KB5078885 directly after 6216, skipping KB5075912 SSU entirely
    (`Step3-BuildIncrementalISOs.ps1 -TargetBuild 7058direct`). Tests whether the
    SSU conflict is what triggers 14099.
- KB5075912 CU intentionally skipped offline: CU CAB causes CBS error 14099 / 0x800f0830
  that permanently damages the component store. SSU CAB applied in isolation only.
- KB5078885 MSU apply also produces 14099 despite ntoskrnl reaching build 7058. Export
  cleans pending transactions but CBS metadata inconsistency persists.
- `autounattend.xml`: DynamicUpdate disabled (pre-patched image), explicit image index
  (`/IMAGE/INDEX = 1`), `WillShowUI OnError` for ProductKey. No FirstLogonCommands.
- `boot.wim` patched with SSU-6935 from KB5075912 to resolve WinPE version mismatch
  against a 7058-level install image.
- `Step3-BuildIncrementalISOs.ps1` now accepts `-TargetBuild` parameter with tab-complete.

---

### v0.3 — 2026-03-28

| Field | Value |
|---|---|
| Base Build | 19045.3803 (22H2) |
| Offline WIM Build | 19045.7058 |
| Updates Offline | KB5039299, KB5050081, KB5063709, KB5075912 (SSU only), KB5078885 |
| Apps Added | _(none yet)_ |
| Output ISO | Win10Pro_22H2_19045.7058.iso |

**Notes:**
- KB5078885 applied offline via MSU — DISM reports exit 14099 but ntoskrnl reaches 7058.
- WIM exported post-update to strip pending component store transactions.
- boot.wim SSU-patched (SSU-6935) to resolve WinPE vs install image version mismatch.
- `autounattend.xml` iterated through multiple fixes: ProductKey WillShowUI, explicit
  image index, DynamicUpdate disabled, FirstLogonCommands removed.
- ISO installs successfully to desktop when autounattend is absent (manual install test).
- Setup failure "corrupted installation file" persists with autounattend — root cause
  traced to CBS 14099 in WIM, not autounattend. Escalated to v0.4 investigation.

---

### v0.2 — 2026-03-27

| Field | Value |
|---|---|
| Base Build | 19045.3803 (22H2) |
| Updates Integrated | KB5078885 |
| Apps Added | _(none yet)_ |
| Output ISO | _(pending build)_ |

**Notes:**
- KB5078885 offline integration attempted directly on 3803 base — failed.
  SSU 7052 (KB5081263) bundled in KB5078885 requires full boot context; DISM offline
  returns `ERROR_ADVANCED_INSTALLER_FAILED` (0x80073713) on CAB extraction path.
- KB5075912 offline also attempted — CU CAB fails error 14099 after SSU CAB.
- Began bridge update research to advance SSU before applying March 2026 CU.

---

### v0.1 — 2026-03-27

| Field | Value |
|---|---|
| Base Build | 19045.3803 (22H2) |
| Updates Integrated | _(none)_ |
| Apps Added | _(none)_ |

**Notes:**
- Initial project setup. Repository structure and documentation scaffolded.
