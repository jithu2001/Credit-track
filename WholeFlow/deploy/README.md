WholeFlow for the Tally PC - install and update guide
=====================================================

What is in this folder
----------------------
  wholeflow.exe            the app (Tally dashboards + background cloud sync)
  Install-WholeFlow.cmd    double-click this: installs, or updates an existing install
  Install-WholeFlow.ps1    the installer itself (used by the .cmd)
  README.txt               this file
  .env.example             optional settings; rename to .env (next to the .cmd) only if needed
  migrations\              database files; the WholeFlow server applies them, nothing to do here

(On the development PC this package is built by deploy\Build-Release.ps1,
or on Linux by deploy/build-release.sh.)

Before you start
----------------
  1. The business exists in the admin app (https://admin.jitsuji.xyz).
     You need its REFERENCE KEY and an ACTIVATION CODE (business page ->
     "Add a Tally PC"). A code works once and expires after 48 hours.
  2. Your WholeFlow admin account (email + password, same as the admin app).
     The PC needs INTERNET to sign in: every sign-in is checked by the
     WholeFlow server. There is no local or offline login.
  3. An Administrator account on this PC (for the UAC prompt).
  4. TallyPrime: F1 Help > Settings > Connectivity > Client/Server
     configuration > "TallyPrime acts as" = Server (or Both).
     The company must be open in Tally for the sync to work.

Which case are you in?
----------------------
  Look for C:\Program Files\WholeFlow\wholeflow.exe.
    - Not there                          -> A. FIRST-TIME INSTALL
    - There (any older version)          -> B. UPDATE
  To see the installed version, open "Command Prompt (Admin)" and run:
    "C:\Program Files\WholeFlow\wholeflow.exe" status

A. FIRST-TIME INSTALL
---------------------
  1. Right-click the zip > Extract All. Open the extracted folder
     (do not run anything from inside the zip).
  2. Double-click Install-WholeFlow.cmd and click Yes on the UAC prompt.
     If SmartScreen warns: "More info" > "Run anyway".
     It installs the Windows service "WholeFlow" (starts at boot, hidden)
     and opens http://127.0.0.1:8080 in the browser.
  3. Sign in with your WholeFlow admin account.
  4. Open "Cloud Sync":
       Step 1  Reference key + Activation code > Connect
               (shows "Connected to <business>")
       Step 2  Test cloud connection
       Step 3  Test Tally & discover companies > tick the companies
               (no more than the plan allows)
       Step 4  Save settings
       Step 5  Sync now (first sync uploads everything: a few minutes)
       Step 4  tick "Background synchronisation enabled" > Save settings
  5. Check: reboot the PC, wait a few minutes, then in Command Prompt (Admin):
       "C:\Program Files\WholeFlow\wholeflow.exe" status
     Expect: service running, the new version, "Connected to <business>",
     and "Last successful sync" for each ticked company.
     In the admin app the PC appears under "Tally PCs" with its version.

B. UPDATE (an older WholeFlow is installed)
-------------------------------------------
  Settings and sync progress are kept (C:\ProgramData\WholeFlow).
  1. Extract the zip, double-click Install-WholeFlow.cmd, click Yes.
     It prints "Upgrading WholeFlow <old> -> <new>", replaces the program,
     restarts the service and prints the status.
  2. Open http://127.0.0.1:8080 and sign in with your WholeFlow admin
     account. The OLD local login (e.g. "admin") NO LONGER WORKS: it is
     deleted on the first start of 0.4.1 or later.
  3a. PC already connected with a reference key (0.4.x): nothing else to do.
      Check "status" shows the new version and a new "Last successful sync".
  3b. PC still syncing to Supabase (0.2 / 0.3): it keeps syncing to Supabase
      as before. To move it to the WholeFlow server, open Cloud Sync:
        Step 1  Reference key + Activation code > Connect
        Step 2  Test cloud connection
        Step 3  check the ticked companies (plan limit applies)
        Step 4  Save settings
        Step 5  Sync now (automatically a FULL sync: all history is uploaded)
        Step 4  keep "Background synchronisation enabled" ticked > Save settings
      Afterwards owner and staff use the phone apps with the reference key.
      Phone logins do not move from Supabase: the owner uses the login from
      the admin app and adds staff again in the Owner app.

Replacement PC
--------------
  New activation code (admin app > business > "Add a Tally PC"), install as
  in A on the new PC, then "Revoke" the old PC in the admin app.

No Administrator account on the PC
----------------------------------
  Copy wholeflow.exe to e.g. C:\Users\<user>\WholeFlow, open a normal
  Command Prompt there and run:  wholeflow.exe autostart
  It then starts hidden at every logon of that user. Continue from A, step 3.

Remove
------
  Install-WholeFlow.cmd -Uninstall      (add -PurgeData to also delete
                                         C:\ProgramData\WholeFlow)

Going back to the previous version
----------------------------------
  Install the previous zip the same way. Do not go below 0.4.0 once the PC
  is connected with a reference key.

When something is wrong
-----------------------
  "This activation code is wrong, already used or expired"
        -> get a new code: admin app > business > "Add a Tally PC".
  "Your plan allows N companies"
        -> untick a company, or change the plan in the admin app.
  "Subscription ended - sync paused"
        -> record the payment in the admin app; the PC resumes by itself.
  "This PC's access was revoked"
        -> it was revoked in the admin app; connect with a new code.
  "Cannot reach the WholeFlow server to check your login"
        -> the PC has no internet. Sign-in needs the server; the background
           sync carries on by itself.
  Tally "Not connected"
        -> open TallyPrime with the company loaded, in Server mode.
  Port 8080 already in use
        -> put APP_ADDR=127.0.0.1:8090 in a .env next to the .cmd, install again.
  "access denied" from status
        -> use Command Prompt (Admin).
  Details: C:\ProgramData\WholeFlow\logs\app.log
           (also at the bottom of the Cloud Sync page)
