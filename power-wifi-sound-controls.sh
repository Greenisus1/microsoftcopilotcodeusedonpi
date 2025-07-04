#!/bin/bash
# 💡 Liam's Pi Guardian Interface — Power, Wi-Fi, Sound, Hotspot Launcher

main_menu() {
  clear
  echo "🔧 Liam's Pi Control Suite"
  echo "1) Power controls"
  echo "2) Connect to Wi-Fi"
  echo "3) Sound settings"
  echo "4) Launch Hotspot"
  echo "5) Exit"
  read -p "Select option: " opt
  case "$opt" in
    1) power_controls ;;
    2) connect_wifi ;;
    3) sound_controls ;;
    4) launch_hotspot ;;
    5) exit 0 ;;
    *) echo "Invalid." && sleep 1 ;;
  esac
}

power_controls() {
  echo "🧠 Power Options"
  echo "1) Restart  2) Shutdown  3) Update  4) Back"
  read -p "Select: " p
  case "$p" in
    1) sudo reboot ;;
    2) sudo shutdown now ;;
    3) sudo apt update && sudo apt upgrade -y ;;
    4) main_menu ;;
  esac
}

connect_wifi() {
  echo "[🌐] Scanning networks..."
  mapfile -t nets < <(nmcli -t -f SSID dev wifi | grep -v '^$')
  for i in "${!nets[@]}"; do echo "$i) ${nets[$i]}"; done
  read -p "Choose #: " c
  read -p "Password for ${nets[$c]}: " pw
  nmcli dev wifi connect "${nets[$c]}" password "$pw"
}

sound_controls() {
  echo "🔊 Sound Settings"
  echo "1) Mute  2) Unmute  3) Volume Up  4) Volume Down  5) Back"
  read -p "Choice: " v
  case "$v" in
    1) amixer set Master mute ;;
    2) amixer set Master unmute ;;
    3) amixer set Master 5%+ ;;
    4) amixer set Master 5%- ;;
    5) main_menu ;;
  esac
}

launch_hotspot() {
  echo "🚀 Launching hotspot monitor in second terminal..."
  lxterminal -t "HOTSPOTLOGANDSHUTDOWN" -e bash -c \
    "curl -fsSL https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/wifihotspotforpipack.sh | bash"
}

while true; do main_menu; done
