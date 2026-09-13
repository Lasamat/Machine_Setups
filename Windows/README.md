# How to use

- Open PowerShell
- Run the script from any directory:
```powershell
powershell -ExecutionPolicy Bypass -File "G:\Repository\Machine_Setups\Windows\linkconfig.ps1"
```
- The current user is detected automatically; the script re-launches itself with
  administrator privileges (a UAC prompt appears) to create the symlinks.
- Existing non-link files are backed up to `<name>.bak-<timestamp>` before being
  replaced.
- After linking, GlazeWM's config is reloaded automatically (`wm-reload-config`).

Edit configs in this repo; changes take effect on the next config reload
(`alt+shift+r`) or by running this script again.