#!/bin/bash
# 💡 Liam's Expanded Pi Control Suite — For Administrative Review

PASSWORD_FOR_OS="LiamsSecretPass123"

main_menu() {
  clear
  echo "🔧 Liam's Pi Control Panel"
  echo "1) Power Options"
  echo "2) Wi-Fi Tools"
  echo "3) Sound Tools"
  echo "4) Hotspot Launch"
  echo "5) Exit"
  read -p "Choice: " opt
  case "$opt" in
    1) power_menu ;;
    2) wifi_tools ;;
    3) sound_tools ;;
    4) launch_hotspot ;;
    5) exit ;;
    *) echo "Invalid." && sleep 1 ;;
  esac
}

power_menu() {
  clear
  echo "⚡ Power & Update Controls"
  echo "1) Restart"
  echo "2) Shutdown"
  echo "3) Update Now"
  echo "4) Update in 1 Hour"
  echo "5) Update & Restart"
  echo "6) Update & Shutdown"
  echo "7) Update & Logout"
  echo "8) Logout"
  echo "9) Update Twice"
  echo "10) Uninstall Pi OS"
  echo "11) Replace Pi OS with Linux"
  echo "12) IBM OS Takeover"
  echo "13) Back"
  read -p "Choice: " p
  case "$p" in
    1) sudo reboot ;;
    2) sudo shutdown now ;;
    3) sudo apt update && sudo apt upgrade -y ;;
    4) sleep 3600 && sudo apt update && sudo apt upgrade -y ;;
    5) sudo apt update && sudo apt upgrade -y && sudo reboot ;;
    6) sudo apt update && sudo apt upgrade -y && sudo shutdown now ;;
    7) sudo apt update && sudo apt upgrade -y && pkill -KILL -u "$USER" ;;
    8) pkill -KILL -u "$USER" ;;
    9) sudo apt update && sudo apt upgrade -y && sudo apt update && sudo apt upgrade -y ;;
    10) echo "🛑 Pi OS uninstall stub — operation disabled for safety." ;;
    11) echo "🔄 Replace OS with Linux — placeholder stub only." ;;
    12)
      read -sp "Enter admin password: " pw; echo
      if [[ "$pw" == "$PASSWORD_FOR_OS" ]]; then
        echo "[🔓] Verified. Backing up system..."
        mkdir -p ~/pi_backup_external
        cp -r /etc ~/pi_backup_external 2>/dev/null
        echo "📥 IBM OS installation stub triggered..."
      else
        echo "[⛔] Incorrect password. Aborted."
      fi
      ;;
    13) main_menu ;;
    *) echo "Invalid." ;;
  esac
}

wifi_tools() {
  echo "🌐 Wi-Fi Management"
  echo "1) Scan & Connect"
  echo "2) Show Saved Networks"
  echo "3) Forget Network"
  echo "4) Back"
  read -p "Choice: " w
  case "$w" in
    1)
      mapfile -t nets < <(nmcli -t -f SSID dev wifi | grep -v '^$')
      for i in "${!nets[@]}"; do echo "$i) ${nets[$i]}"; done
      read -p "Select #: " idx
      read -p "Password for ${nets[$idx]}: " pw
      nmcli dev wifi connect "${nets[$idx]}" password "$pw"
      ;;
    2) nmcli connection show ;;
    3)
      read -p "Enter SSID to forget: " ssid
      nmcli connection delete "$ssid"
      ;;
    4) main_menu ;;
    *) echo "Invalid." ;;
  esac
}

sound_tools() {
  echo "🔊 Sound Controls"
  echo "1) Mute"
  echo "2) Unmute"
  echo "3) Volume Up"
  echo "4) Volume Down"
  echo "5) Test Audio"
  echo "6) Back"
  read -p "Choice: " s
  case "$s" in
    1) amixer set Master mute ;;
    2) amixer set Master unmute ;;
    3) amixer set Master 10%+ ;;
    4) amixer set Master 10%- ;;
    5) speaker-test -t sine -f 1000 -l 1 ;;
    6) main_menu ;;
    *) echo "Invalid." ;;
  esac
}

launch_hotspot() {
  echo "🚀 Launching hotspot monitor in new terminal..."
  lxterminal -t "HOTSPOTLOGANDSHUTDOWN" -e bash -c \
    "curl -fsSL https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/wifihotspotforpipack.sh | bash"
}

while true; do main_menu; done
