# Build Process

Step-by-step workflow for creating the custom Windows 10 Pro 22H2 image.

---

## Overview

```
Source ISO  →  Extract  →  Mount WIM  →  Integrate Updates  →  Add Apps/Configs
           →  Unmount & Commit  →  Repackage ISO  →  Test
```

---

## Step 1 — Prepare the Build Environment

1. Install Windows ADK (Deployment Tools + Windows SIM). See [tools-required.md](tools-required.md).
2. Working directory layout for this build:

```
V:\RWJBH-Lab\
├── ISOs\Win10\       # Source ISO and downloaded .msu update files
├── Scratch\          # DISM scratch space (temp)
└── GitHub\Win10Pro_Build\
    ├── logs\         # DISM and script output logs
    └── scripts\      # PowerShell build scripts

E:\                   # WIM mount point (mounted image)
```

3. Open an **elevated (Administrator) PowerShell prompt** for all DISM operations.

---

## Step 2 — Mount or Extract the Source ISO

Mount the ISO via Windows Explorer (right-click → Mount) or assign it a drive letter.
For this build `Windows10.iso` mounts at **E:\**.

> Note: The Media Creation Tool ISO uses a dual-arch layout. Sources are under `D:\x64\sources\`
> not the usual `D:\sources\`.

If you prefer to work from extracted files:
```
robocopy D:\ V:\RWJBH-Lab\ISOs\Win10\ISO\ /E
```

---

## Step 3 — Identify the Target Image Index

The `install.esd` contains multiple edition indexes.

```powershell
dism /Get-WimInfo /WimFile:"E:\x64\sources\install.esd"
```

Note the **Index** number for **Windows 10 Pro**.

---

## Step 3b — Convert ESD to WIM (required for this build)

The source ISO contains `install.esd` (compressed, read-only). DISM cannot
integrate updates into an ESD directly — it must be exported to a writable WIM first.

```powershell
# Export Windows 10 Pro index (index 6) to a writable WIM
dism /Export-Image /SourceImageFile:"E:\x64\sources\install.esd" /SourceIndex:6 `
     /DestinationImageFile:"V:\RWJBH-Lab\ISOs\Win10\install.wim" /Compress:max /CheckIntegrity
```

> Or use the script: `scripts\Step1-ExportAndMount.ps1` (handles detection, export, and mount in one step)

---

## Step 4 — Mount the Install Image

```powershell
dism /Mount-Image /ImageFile:"V:\RWJBH-Lab\ISOs\Win10\install.wim" `
     /Index:1 /MountDir:"V:\RWJBH-Lab\Mount"
```

---

## Step 5 — Integrate Cumulative Updates

See [updates.md](updates.md) for the full update list and per-KB notes.

KB5078885 (Mar 2026 CU, 19045.7058) **cannot be applied offline** — its SSU 7052 advanced
installer requires full boot context. Instead:

- **Offline (WIM):** KB5039299 + KB5050081 → leaves image at 19045.5440
- **First logon:** KB5078885 installed via `autounattend.xml` `FirstLogonCommands` → final build 19045.7058

```powershell
# Run the update integration script (applies KB5039299 + KB5050081 offline)
scripts\Invoke-UpdateIntegration.ps1
```

The script expects the image already mounted. It stops at 19045.5440 and reports SUCCESS.
KB5078885 is staged into the image in Step 8 (Invoke-CleanupAndUnmount.ps1).

Verify integrated packages:
```powershell
dism /Image:"V:\RWJBH-Lab\Mount" /Get-Packages
```

---

## Step 6 — Add Pre-installed Applications

Options for pre-installing apps:

**Provisioned AppX packages (Store apps):**
```powershell
dism /Image:"C:\WinBuild\Mount" /Add-ProvisionedAppxPackage `
     /PackagePath:"<app.msixbundle>" /SkipLicense
```

**Offline MSI/silent installers** — not directly supported via DISM offline; handle via the autounattend `FirstLogonCommands` or a post-install script instead.

See [../scripts/](../scripts/) for post-install automation.

---

## Step 7 — Apply autounattend.xml

The answer file at `autounattend\autounattend.xml` includes `FirstLogonCommands` that
install KB5078885 on first logon (from `C:\Updates\` in the image — staged in Step 8).

**Before using the answer file, edit it and replace `CHANGEME`** in the `<Password>` and
`<AutoLogon>` sections with the intended local admin password. See
[../autounattend/README.md](../autounattend/README.md) for validation steps.

Copy the answer file to the root of the ISO or USB before booting:
```powershell
Copy-Item "V:\RWJBH-Lab\GitHub\Win10Pro_Build\autounattend\autounattend.xml" `
          "<ISO root>\" -Force
```

---

## Step 8 — Stage KB5078885, Clean Up, and Unmount

`Invoke-CleanupAndUnmount.ps1` does the following in order:
1. Copies KB5078885.msu from `V:\RWJBH-Lab\ISOs\Win10\` into `C:\Updates\` in the mounted WIM
2. Runs `dism /Cleanup-Image /StartComponentCleanup /ResetBase` to reduce WIM size
3. Unmounts and commits the image

```powershell
scripts\Invoke-CleanupAndUnmount.ps1
```

> Run as Administrator. KB5078885.msu must be present in `V:\RWJBH-Lab\ISOs\Win10\` before running.

---

## Step 9 — Export the Image (Optional — reduce file size)

```powershell
dism /Export-Image /SourceImageFile:"C:\WinBuild\ISO\sources\install.wim" `
     /SourceIndex:<Pro_Index> `
     /DestinationImageFile:"C:\WinBuild\ISO\sources\install_export.wim" `
     /Compress:max
```

Replace `install.wim` with the exported file if size reduction is significant.

---

## Step 10 — Repackage into Bootable ISO

Use `oscdimg` from the Windows ADK:

```powershell
oscdimg -m -o -u2 -udfver102 `
        -bootdata:2#p0,e,b"C:\WinBuild\ISO\boot\etfsboot.com"#pEF,e,b"C:\WinBuild\ISO\efi\microsoft\boot\efisys.bin" `
        "C:\WinBuild\ISO\" `
        "C:\WinBuild\Output\Win10Pro_22H2_Custom.iso"
```

---

## Step 11 — Test

1. Mount the ISO in a VM (Hyper-V, VMware, VirtualBox).
2. Boot from the ISO and verify:
   - Setup completes without errors
   - Correct edition (Pro) is installed
   - Cumulative updates are present (`winver` / `Settings → Windows Update`)
   - Pre-installed apps are present
   - Post-install scripts run successfully

---

## Troubleshooting

| Symptom | Check |
|---|---|
| DISM errors during update integration | Verify SSU is applied before CU; check DISM log at `C:\Windows\Logs\DISM\dism.log` |
| ISO won't boot | Verify `etfsboot.com` and `efisys.bin` paths in oscdimg command |
| Wrong edition installed | Confirm the correct WIM index was used |
| `install.esd` present instead of `.wim` | Follow the ESD → WIM conversion step above |
