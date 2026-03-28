# scripts

Post-install PowerShell and batch scripts that run after Windows Setup completes.

---

## Execution Context

Scripts are triggered via `FirstLogonCommands` in `autounattend.xml` or by the local Administrator account on first logon. All scripts must be compatible with **PowerShell 5.1** (inbox on Windows 10).

---

## Scripts

| Script | Purpose | Status |
|---|---|---|
| `Step1-ExportAndMount.ps1` | Export Pro index from install.esd to install.wim, then mount | Ready |
| `Invoke-UpdateIntegration.ps1` | Apply cumulative updates to the mounted WIM via DISM | Ready |
| `Invoke-CleanupAndUnmount.ps1` | Run component cleanup, unmount, and commit the image | Ready |
| `Set-WindowsDefaults.ps1` | Apply system-wide defaults (power plan, explorer settings, etc.) | Planned |
| `Install-Apps.ps1` | Silently install pre-approved applications | Planned |
| `Remove-Bloatware.ps1` | Remove unwanted provisioned AppX packages | Planned |
| `Apply-Registry.ps1` | Import registry tweaks from `configs/` | Planned |
| `Invoke-WindowsUpdate.ps1` | Trigger Windows Update on first boot to catch any delta patches | Planned |

---

## Conventions

- All scripts must be **idempotent** — safe to run more than once without side effects.
- Use `Write-Host` / `Out-File` logging to `C:\Windows\Logs\Build\` so execution can be audited.
- Exit with code `0` on success; non-zero on failure (Setup uses this for error detection).
- No hardcoded credentials, hostnames, or environment-specific paths.
