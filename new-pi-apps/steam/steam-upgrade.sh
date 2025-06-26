#!/bin/bash
# STEAMFIXER [BETA] - Motel Manager Simulator Launcher & System Utility

# CONFIG
GAME_APPID="2594540"  # Replace with actual App ID
REQUIRED_SPACE_MB=3000
STEAM_CMD="steam steam://rungameid/$GAME_APPID"
TEMP_OUTPUT="/tmp/steamfixer_output.txt"

# ASCII Pi Logo Banner (fallback for terminal)
show_banner() {
  clear
  echo "============================================================"
  echo "   _____ _                                 _  __ _           "
  echo "  / ____| |                               (_)/ _(_)          "
  echo " | (___ | |_ _ __ ___  __ _ _ __ ___   ___ _| |_ _  ___ ___  "
  echo "  \___ \| __| '__/ _ \/ _\` | '_ \` _ \ / _ \ |  _| |/ __/ _ \ "
  echo "  ____) | |_| | |  __/ (_| | | | | | |  __/ | | | | (_|  __/ "
  echo " |_____/ \__|_|  \___|\__,_|_| |_| |_|\___|_|_| |_|\___\___| "
  echo "                                                             "
  echo "                  STEAMFIXER [BETA]    BY:GREENISUS1         "
  echo "============================================================"
  sleep 2
}

# Auto-install dialog if missing
if ! command -v dialog &>/dev/null; then
  echo "[INFO] 'dialog' not found. Installing..."
  
  sudo apt update && sudo apt install -y dialog
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] Failed to install 'dialog'. Exiting."
    exit 1
  fi
fi

# Main menu
main_menu() {
  dialog --backtitle "STEAMFIXER [BETA]" \
         --title "Main Menu" \
         --menu "Choose an action:" 15 60 6 \
         1 "Check Disk Space" \
         2 "Check Graphics Drivers" \
         3 "Verify Steam Installation" \
         4 "Enable Proton" \
         5 "Launch Motel Manager" \
         6 "Exit" 2>"$TEMP_OUTPUT"

  CHOICE=$(<"$TEMP_OUTPUT")
  case $CHOICE in
    1) check_disk_space ;;
    2) check_graphics_driver ;;
    3) check_steam ;;
    4) enable_proton ;;
    5) launch_game ;;
    6) clear; exit 0 ;;
    *) main_menu ;;
  esac
}

check_disk_space() {
  AVAIL_MB=$(df --output=avail "$HOME" | tail -n 1)
  AVAIL_MB=$((AVAIL_MB / 1024))
  if (( AVAIL_MB < REQUIRED_SPACE_MB )); then
    dialog --msgbox "Disk Space: ${AVAIL_MB}MB available.\n⚠️ Not enough to run the game!" 10 50
  else
    dialog --msgbox "Disk Space: ${AVAIL_MB}MB available.\n✅ You're good to go!" 10 50
  fi
  main_menu
}

check_graphics_driver() {
  INFO=$(glxinfo | grep "OpenGL renderer" 2>/dev/null)
  if [[ -z "$INFO" ]]; then
    dialog --msgbox "⚠️ Unable to detect graphics driver.\nMake sure Mesa or proprietary drivers are installed." 10 50
  else
    dialog --msgbox "✅ Detected GPU:\n$INFO" 10 50
  fi
  main_menu
}

check_steam() {
  if ! command -v steam &>/dev/null; then
    dialog --msgbox "❌ Steam is not installed or not in PATH." 10 50
  else
    dialog --msgbox "✅ Steam is installed and ready." 10 50
  fi
  main_menu
}

enable_proton() {
  mkdir -p "$HOME/.steam/steam/compatibilitytools.d"
  CONFIG="$HOME/.steam/steam/config/config.vdf"
  if ! grep -q '"EnableSteamPlay"' "$CONFIG" 2>/dev/null; then
    sed -i 's/"CompatToolMapping"/"EnableSteamPlay" "1"\n\t\t\t"CompatToolMapping"/' "$CONFIG"
    dialog --msgbox "🛠️ Proton support toggled.\n(Note: Settings may reset on Steam updates.)" 10 50
  else
    dialog --msgbox "✅ Proton is already enabled." 10 50
  fi
  main_menu
}

launch_game() {
  ($STEAM_CMD &)
  dialog --msgbox "🚀 Launching Motel Manager Simulator..." 10 50
  main_menu
}

# Run
show_banner
main_menu
