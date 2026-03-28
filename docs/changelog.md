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

### v0.3 — 2026-03-28

| Field | Value |
|---|---|
| Base Build | 19045.3803 (22H2) |
| Offline WIM Build | 19045.5440 |
| Final Installed Build | 19045.7058 (after first-logon KB5078885) |
| Updates Offline | KB5039299, KB5050081 |
| Updates First-Logon | KB5078885 |
| Apps Added | _(none yet)_ |
| Output ISO | _(pending build)_ |

**Notes:**
- KB5078885 offline integration blocked: SSU 7052 (KB5081263) fails with
  `ERROR_ADVANCED_INSTALLER_FAILED` (0x80073713) — advanced installer requires full boot context.
- KB5075912 offline also blocked: CU CAB fails error 14099 after SSU CAB.
- New strategy: image ships at 19045.5440; KB5078885 MSU staged in `C:\Updates\` and
  installed on first logon via `autounattend.xml` `FirstLogonCommands`.
- `autounattend.xml` created with UEFI/GPT disk layout, OOBE skip, auto-logon, and
  `FirstLogonCommands` for KB5078885 → restart.

---

### v0.2 — 2026-03-27

| Field | Value |
|---|---|
| Base Build | 19045.3803 (22H2) |
| Post-Update Build | 19045.7058 |
| Updates Integrated | KB5078885 |
| Apps Added | _(none yet)_ |
| Output ISO | _(pending build)_ |

**Updates integrated:**

| KB | Type | Release Date | Build After | Size (x64) | Notes |
|---|---|---|---|---|---|
| KB5078885 | Cumulative Update | 2026-03-10 | 19045.7058 | ~846 MB | March 2026 Patch Tuesday; GPU stability fix; Secure Boot 2023 certs |

**Notes:**
- No separate Servicing Stack Update (SSU) required as prerequisite — SSU is bundled in modern Windows 10 22H2 CUs.
- Addresses 78 vulnerabilities (March 2026 Patch Tuesday).
- Includes updated Secure Boot 2023 certificates (older certs expire June 2026).

---

### v0.1 — 2026-03-27

| Field | Value |
|---|---|
| Base Build | 19045.3803 (22H2) |
| Updates Integrated | _(none)_ |
| Apps Added | _(none)_ |

**Notes:**
- Initial project setup. Repository structure and documentation scaffolded.
