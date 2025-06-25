### ✅ v1.0 — Initial Build
- Basic script to remove old Steam installs
- Installed Box64, Box86, Wine, and Steam
- Created logs and printed launch instructions

### 🔁 v1.1 — Retry Logic + Logging
- Wrapped commands in \`run_step\` with success/failure messages
- Added \`steam_install_log.txt\` with timestamps
- Prompted to retry failed steps manually

### 💾 v1.2 — GitHub Backup + Emergency Mode
- Added full-system backup option on failure
- Created private GitHub repo using user PAT
- Uploaded \`/etc\` and \`/home\` to the repo
- Optionally deleted the repo if Steam installed successfully

### 🎨 v1.3 — DVD Animation Feature
- Fullscreen ASCII “DVD” animation during install
- Bounces text, cycles colors, monitors CPU load
- Auto-pauses on high system load or critical operations

### 🧠 v1.4 — Failsafe Reboot + Resume
- Introduced \`--resume\` flag to continue after reboot
- Created resume flag file \`/tmp/steam_resume.flag\`
- Cleaned up partial installs on critical failure + reboot

### 🧽 v1.5 — Animation Safety Fix
- Delayed animation until after all sensitive input prompts
- Prevented animation from interrupting GitHub PAT entry
- Restored console state even on hard failure`);
