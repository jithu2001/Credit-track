# WholeFlow client package

Build it on the development PC with `deploy\Build-Release.ps1`; it produces
`dist\WholeFlow-<version>.zip` containing:

```
wholeflow.exe            the app (web dashboard + background cloud sync)
Install-WholeFlow.cmd    double-click this: installs, or upgrades an existing install
Install-WholeFlow.ps1    the installer itself
README.txt               this file
.env.example             optional overrides; rename to .env next to the installer to use it
migrations\              Supabase SQL files (apply new ones in the SQL Editor before updating PCs)
```

**New PC:** extract the zip, double-click `Install-WholeFlow.cmd`, accept the
UAC prompt, then create the admin account and set up Cloud Sync in the browser
page that opens.

**Update:** extract the new zip, double-click `Install-WholeFlow.cmd`, accept
the UAC prompt. It stops the service, replaces the exe, starts it again and
prints the status with the new version. Settings, login and sync state are
kept. Rolling back = installing the previous zip the same way.

**Remove:** `Install-WholeFlow.cmd -Uninstall` (add `-PurgeData` to also delete
`C:\ProgramData\WholeFlow`).

No Administrator account on the PC? Use `wholeflow.exe autostart` instead of
the installer. Full steps: README.md in the source, sections "Deploying on a
client PC" and "Rolling out an update".
