#!/bin/bash

# power-wifi-sound-controls.sh
# Full-feature utility by Liam + Copilot
# Dependencies: curl, nmcli, w3m, tmux, alsa-utils, upower, rfkill

# ----------- Startup: Ensure bettersound.sh is installed and run ------------
echo "[🔧] Preparing better sound system..."

BETTERSOUND_URL="https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/bettersound.sh"
BETTERSOUND_PATH="/usr/local/bin/bettersound.sh"

if ! command -v curl &> /dev/null; then
  echo "[⚠️] curl not found. Installing..."
  apt update && apt install -y curl
fi

if [ ! -f "$BETTERSOUND_PATH" ]; then
  echo "[📥] Downloading bettersound.sh..."
  curl -L "$BETTERSOUND_URL" -o "$BETTERSOUND_PATH"
  chmod +x "$BETTERSOUND_PATH"
else
  echo "[✔️] bettersound.sh already installed."
fi

echo "[🚀] Executing bettersound.sh..."
"$BETTERSOUND_PATH"

# ----------- Utility Functions ------------------

get_signal_bar() {
  strength=$1
  case $strength in
    [0-9]|1[0-9]) echo "▁▁▁▁▁" ;;
    2[0-9]|3[0-9]) echo "▂▁▁▁▁" ;;
    4[0-9]|5[0-9]) echo "▂▃▁▁▁" ;;
    6[0-9]|7[0-9]) echo "▂▃▄▁▁" ;;
    8[0-9]|9[0-9]|100) echo "▂▃▄▅▆" ;;
    *) echo "?" ;;
  esac
}

is_captive() {
  status=$(curl -s -o /dev/null -w "%{http_code}" http://connectivity-check.gstatic.com/generate_204)
  [[ "$status" != "204" ]]
}

open_captive_terminal() {
  portal_url="http://neverssl.com"
  echo "[🖥️] Launching captive browser in terminal..."
  tmux new-session -d -s captive_browser "w3m $portal_url; read -p 'Press enter to exit captive browser...'"
}

# ----------- Menu Logic ------------------

show_menu() {
  clear
  echo "===== Power, WiFi, and Sound Controls ====="
  echo "1) Power Status"
  echo "2) WiFi Controls"
  echo "3) Sound Controls"
  echo "4) Exit"
  echo "Choose an option:"
}

check_power() {
  echo "--- Battery & Power Info ---"
  upower -i /org/freedesktop/UPower/devices/line_power_AC | grep -E "online"
  echo ""
}

wifi_controls() {
  echo "--- WiFi Controls ---"
  echo "1) View Status"
  echo "2) Toggle WiFi"
  echo "3) Create Hotspot"
  echo "4) Relay Hotspot from Existing WiFi"
  echo "5) Connect to Wi-Fi Network"
  read -p "Select: " wifi_opt

  case $wifi_opt in
    1) iwconfig ;;
    2) rfkill list wifi && rfkill unblock wifi && echo "WiFi toggled." ;;
    3)
      read -p "Hotspot SSID: " ssid
      read -p "Password (8+ chars): " pass
      nmcli dev wifi hotspot ifname wlan0 ssid "$ssid" password "$pass"
      ;;
    4)
      read -p "Source SSID: " src_ssid
      read -p "Source Password: " src_pass
      read -p "Relay SSID: " relay_ssid
      read -p "Relay Password: " relay_pass
      nmcli dev wifi connect "$src_ssid" password "$src_pass"
      nmcli dev wifi hotspot ifname wlan1 ssid "$relay_ssid" password "$relay_pass"
      ;;
    5) connect_to_wifi ;;
    *) echo "Invalid option" ;;
  esac
}

connect_to_wifi() {
  echo "[📶] Scanning for Wi-Fi networks..."
  base_dir="$HOME/power-wifi-controls/wifi-passwords"
  mkdir -p "$base_dir"

  mapfile -t network_list < <(nmcli -t -f SSID,SECURITY,SIGNAL dev wifi | grep -v '^:' | sort -u)

  declare -a ssids
  i=1
  for entry in "${network_list[@]}"; do
    IFS=: read -r ssid security signal <<< "$entry"
    [ -z "$ssid" ] && continue
    ssids+=("$ssid")

    bar=$(get_signal_bar "$signal")
    pass_file="$base_dir/$ssid.txt"

    captive=""
    if is_captive; then captive="(CAPTIVE)"; fi

    if [[ "$security" == "--" || -f "$pass_file" ]]; then
      icon="🔓"
    else
      icon="🔒"
    fi

    echo "$i) $ssid [$bar $signal%] $icon $captive"
    ((i++))
  done

  read -p "Choose a network number: " choice
  ssid="${ssids[$((choice-1))]}"
  pass_file="$base_dir/$ssid.txt"

  if [[ -f "$pass_file" ]]; then
    echo "[🔐] Using saved password for $ssid."
    password=$(<"$pass_file")
  elif [[ "$security" != "--" ]]; then
    read -p "Enter password for $ssid (only needed once): " password
    echo "$password" > "$pass_file"
  fi

  echo "[🔄] Connecting to $ssid..."
  if nmcli dev wifi connect "$ssid" password "$password"; then
    echo "[✅] Connected successfully."

    if is_captive; then
      echo "[🌐] Captive portal detected."
      open_captive_terminal
      mkdir -p "$HOME/power-wifi-controls/captive-verified"
      touch "$HOME/power-wifi-controls/captive-verified/${ssid}.ok"
      echo "[🛡️] Verified captive network saved."
    fi

  else
    echo "[❌] Connection failed."
    read -p "WOULD YOU LIKE TO RESTART YOUR PI/LINUX? (Y,n): " restart_ans
    [[ "$restart_ans" =~ ^[Yy]$ ]] && reboot
  fi
}

sound_controls() {
  echo "--- Sound Controls ---"
  echo "Available Audio Devices:"
  aplay -l | grep '^card'

  read -p "Enter card number (e.g., 0): " card_num
  read -p "Enter device number (e.g., 0): " device_num
  device="hw:${card_num},${device_num}"

  echo "Selected output: $device"
  echo "1) Volume Up"
  echo "2) Volume Down"
  echo "3) Mute / Unmute"
  read -p "Select: " sound_opt

  case $sound_opt in
    1) amixer -D "$device" set Master 5%+ ;;
    2) amixer -D "$device" set Master 5%- ;;
    3) amixer -D "$device" set Master toggle ;;
    *) echo "Invalid option" ;;
  esac
}

# ----------- Main Loop ------------------

while true; do
  show_menu
  read -p "> " choice
  case $choice in
    1) check_power ;;
    2) wifi_controls ;;
    3) sound_controls ;;
    4) echo "Bye!" && exit ;;
    *) echo "Invalid selection" ;;
  esac
  read -p "Press enter to continue..." dummy
done
