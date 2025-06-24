#!/bin/bash
LOGFILE=~/steam_install_log.txt
exec > >(tee -a "$LOGFILE") 2>&1
set -e

log() {
    echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

try() {
    log "$1"
    if ! eval "$2"; then
        log "❌ Failed: $1"
        exit 1
    else
        log "✅ Success: $1"
    fi
}

log "🔧 Starting Steam installation setup for Raspberry Pi..."

try "Removing previous Steam and Wine installations" \
    "rm -rf ~/.steam ~/.local/share/Steam ~/.wine && sudo apt purge -y steam wine64 || true && sudo apt autoremove -y"

try "Updating package lists" \
    "sudo apt update"

try "Installing Box64, Box86, and Wine" \
    "sudo apt install -y box64 box86 wine64 wget"

try "Creating install directory" \
    "mkdir -p ~/steam_pi_install && cd ~/steam_pi_install"

try "Downloading SteamSetup.exe" \
    "wget -O SteamSetup.exe https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"

log "🍷 Running Steam installer with Wine..."
if wine SteamSetup.exe; then
    log "✅ Steam installer launched successfully"
else
    log "❌ Steam installer failed to launch"
    exit 1
fi

LAUNCH_CMD="wine ~/.wine/drive_c/Program\ Files\ \(x86\)/Steam/Steam.exe"
log "🚀 To launch Steam in the future, run:"
echo -e "\n$LAUNCH_CMD\n"

log "🎉 Installation complete. Log saved to $LOGFILE"
