#!/bin/bash
LOGFILE=~/steam_install_log.txt
exec > >(tee -a "$LOGFILE") 2>&1

STEPS=(
  "Remove old Steam and Wine|rm -rf ~/.steam ~/.local/share/Steam ~/.wine && sudo apt purge -y steam wine64 || true && sudo apt autoremove -y"
  "Update packages|sudo apt update"
  "Install Box64 and Box86|sudo apt install -y box64-rpi4arm64 box86-rpi4arm64:armhf"
  "Install Wine and wget|sudo apt install -y wine64 wget"
  "Create install directory|mkdir -p ~/steam_pi_install"
  "Download SteamSetup.exe|wget -O ~/steam_pi_install/SteamSetup.exe https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
  "Run Steam installer|cd ~/steam_pi_install && wine SteamSetup.exe"
)

log() {
  echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

run_step() {
  local step="$1"
  local name="${step%%|*}"
  local command="${step#*|}"

  while true; do
    log "🔧 $name"
    if eval "$command"; then
      log "✅ Success: $name"
      return 0
    else
      log "❌ Failed: $name"
      read -rp "❓ Do you want to retry this step? (Y,n): " yn
      case $yn in
        [Yy]* ) log "🔁 Retrying $name...";;
        [Nn]* ) log "⏭️ Skipped: $name"; return 1;;
        * ) echo "Please enter Y or n.";;
      esac
    fi
  done
}

log "🚀 Starting Steam setup for Raspberry Pi..."

for step in "${STEPS[@]}"; do
  run_step "$step"
done

LAUNCH_CMD="wine ~/.wine/drive_c/Program\\ Files\\ \\(x86\\)/Steam/Steam.exe"
log "🎯 All done! To launch Steam in the future, run:"
echo -e "\n$LAUNCH_CMD\n"
log "📝 Installation log saved to $LOGFILE"
