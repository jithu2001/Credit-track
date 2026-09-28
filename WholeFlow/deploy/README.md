# Client installation package

What to copy to the client's Tally PC (one folder, e.g. a USB stick or `Downloads\WholeFlow`):

```
WholeFlow\
  wholeflow.exe            built with: go build -o bin\wholeflow.exe ./cmd/server
  Install-WholeFlow.cmd    double-click this
  Install-WholeFlow.ps1
  .env                     optional (see ..\.env.example); only if you need overrides such as APP_ADDR or TALLY_PORT
```

Then double-click **Install-WholeFlow.cmd**, accept the UAC prompt, and follow the on-screen steps. Full walkthrough: [../README.md → Deploying on a client PC](../README.md#deploying-on-a-client-pc) and [../docs/SYNC_SETUP.md](../docs/SYNC_SETUP.md).

No Administrator account on the client PC? Skip the script and run `wholeflow.exe autostart` instead (see the README).
