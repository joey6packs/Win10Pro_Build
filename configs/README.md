# configs

Configuration files applied during or after Windows Setup.

---

## Contents

| File/Folder | Purpose |
|---|---|
| `registry/` | `.reg` files imported by post-install scripts |
| `appx-remove.txt` | List of provisioned AppX package names to remove |
| `apps-install.txt` | List of applications to install with install parameters |

---

## Registry Files

`.reg` files in `configs/registry/` are imported by `scripts/Apply-Registry.ps1`.

Naming convention: `<scope>-<description>.reg`

Examples:
- `system-explorer-settings.reg`
- `user-default-associations.reg`

---

## App Lists

`apps-install.txt` — one entry per line in the format:

```
# Comment / app name
<installer_filename>  <silent_switch>
```

Example:
```
# 7-Zip
7z_installer.exe  /S
```

`appx-remove.txt` — one provisioned package name per line:

```
Microsoft.BingWeather
Microsoft.GetHelp
Microsoft.Getstarted
```

Use `Get-AppxProvisionedPackage -Online` on a reference machine to identify package names.
