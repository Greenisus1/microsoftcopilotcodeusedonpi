#!/bin/bash
LOGFILE=~/steam_install_log.txt
exec > >(tee -a "$LOGFILE") 2>&1
set -e

CLEANUP_PATHS=(~/.steam ~/.local/share/Steam ~/.wine ~/steam_pi_install)

log() {
  echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

cleanup() {
  log "🧹 Cleaning up temporary files and partial installs..."
  for path in "${CLEANUP_PATHS[@]}"; do
    rm -rf "$path"
  done
}

fatal_exit() {
  log "❌ ERROR: Critical failure encountered."
  echo -e "\n🚨 PLEASE REPORT TO GREENISUS1 ON GITHUB\n❗ Error Code: $1"
  exit "$1"
}

run_step() {
  local name="$1"
  local command="$2"

  log "🔧 $name"
  if eval "$command"; then
    log "✅ Success: $name"
    return 0
  fi

  log "⚠️ Failed: $name. Retrying once..."
  if eval "$command"; then
    log "✅ Success on retry: $name"
    return 0
  fi

  read -rp "❓ Still failing. Try again from a clean slate? (Y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    cleanup
    log "🔁 Retrying after cleanup: $name"
    if eval "$command"; then
      log "✅ Success after cleanup: $name"
      return 0
    else
      fatal_exit 77
    fi
  else
    fatal_exit 88
  fi
}

log "🚀 Starting Steam setup for Raspberry Pi..."

run_step "Removing previous Steam and Wine installations" \
  "sudo apt purge -y steam wine64 || true && sudo apt autoremove -y"

run_step "Updating package lists" \
  "sudo apt update"

run_step "Installing Box64 and Box86" \
  "sudo apt install -y box64-rpi4arm64 box86-rpi4arm64:armhf"

run_step "Installing Wine and wget" \
  "sudo apt install -y wine64 wget"

run_step "Creating install directory" \
  "mkdir -p ~/steam_pi_install"

run_step "Downloading SteamSetup.exe" \
  "wget -O ~/steam_pi_install/SteamSetup.exe https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"

run_step "Running Steam installer" \
  "cd ~/steam_pi_install && wine SteamSetup.exe"

log "🎯 Done! To launch Steam, run:"
echo -e "\nwine ~/.wine/drive_c/Program\\ Files\\ \\(x86\\)/Steam/Steam.exe\n"

log "📝 Full log saved to $LOGFILE"
