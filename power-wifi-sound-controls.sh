#!/bin/bash
# ----------------------------------------------------------------------------
# Liam’s Pi-Connect Guardian
# A single script for Pi: power tools, Wi-Fi connect, hotspot cloning & monitoring,
# user kick/block/rejoin logic, timed hints, and captive portal handling.
# ----------------------------------------------------------------------------

#———— Configuration & Bootstrap ————————————————————————————————————————
ROOT="$HOME/power-wifi-controls"
mkdir -p \
  "$ROOT/wifi-passwords" \
  "$ROOT/wifi-blocked-users" \
  "$ROOT/kicked" \
  "$ROOT/logs" \
  "$ROOT/captive-verified"

LOGFILE="$ROOT/logs/hotspot-log.txt"
REJOIN_CODE="8741-LIAMNET"
MAX_ATTEMPTS=3
HOTSPOT_SSID="PI-CONNECT"
HOTSPOT_PASS="pi-connect-pass"
PASSWORD_FOR_OS="LiamsSecretPass123"

# Ensure dependencies
for cmd in nmcli curl tmux w3m arp avahi-resolve-address iptables lxterminal; do
  command -v $cmd >/dev/null 2>&1 || sudo apt update && sudo apt install -y $cmd
done

#———— Utility Functions ——————————————————————————————————————————

# Signal‐strength → ASCII bar
get_signal_bar() {
  s=$1
  case $s in
    [0-9]|1[0-9]) echo "▁▁▁▁▁" ;;
    2[0-9]|3[0-9]) echo "▂▁▁▁▁" ;;
    4[0-9]|5[0-9]) echo "▂▃▁▁▁" ;;
    6[0-9]|7[0-9]) echo "▂▃▄▁▁" ;;
    8[0-9]|9[0-9]|100) echo "▂▃▄▅▆" ;;
    *) echo "?" ;;
  esac
}

# Captive‐portal check via Google’s 204 URL
is_captive() {
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    http://connectivity-check.gstatic.com/generate_204)
  [[ "$code" != "204" ]]
}

# Launch minimal terminal browser for captive login
open_captive_terminal() {
  tmux new-session -d -s captive_browser \
    "w3m http://neverssl.com; read -p 'Press Enter to exit captive browser…'"
}

# Handle blocked device’s rejoin‐code flow
handle_rejoin() {
  ip="$1"; mac="$2"; name="$3"
  attempts=0
  while (( attempts < MAX_ATTEMPTS )); do
    echo "🔐 Blocked device “$name” ($ip) detected."
    echo "Enter rejoin code:"
    read -r code
    if [[ "$code" == "$REJOIN_CODE" ]]; then
      echo "✅ Access granted for $name."
      rm -f "$ROOT/wifi-blocked-users/$ip.blocked" \
            "$ROOT/wifi-blocked-users/$mac.blocked"
      return
    fi
    (( attempts++ ))
    echo "❌ Wrong code ($attempts/$MAX_ATTEMPTS)."
  done
  echo "🚫 Permanently banning $name."
  {
    echo "Device: $name"
    echo "MAC: $mac"
    echo "IP: $ip"
    echo "Date: $(date)"
  } > "$ROOT/wifi-blocked-users/$mac.blocked"
}

# Hint engine: emits random tips every 30–300s with weights
start_hint_engine() {
  hints=(
    "Press 2 to stop hotspot"
    "Press 3 to edit users"
    "Press 9 to unban a user"
  )
  weights=(5 2 1)
  while true; do
    sleep $(( 30 + RANDOM % 270 ))
    w0=${weights[0]}; w1=${weights[1]}; w2=${weights[2]}
    pick=$(( RANDOM % (w0 + w1 + w2) ))
    if (( pick < w0 )); then echo "[💡] ${hints[0]}"
    elif (( pick < w0 + w1 )); then echo "[💡] ${hints[1]}"
    else echo "[💡] ${hints[2]}"
    fi
  done
}

#———— Hotspot Monitor (launched in new terminal) —————————————————————

monitor_hotspot() {
  echo "Type 1 to start hotspot cloning \"$SSID_TO_CLONE\" → \"$HOTSPOT_SSID\""
  read -n1 k; echo
  if [[ "$k" != "1" ]]; then
    echo "Canceled."; exit 0
  fi

  # connect upstream
  echo "[🔄] Connecting to $SSID_TO_CLONE..."
  nmcli dev wifi connect "$SSID_TO_CLONE" password "$CLONE_PASS"

  # start hotspot
  nmcli connection delete "$HOTSPOT_SSID" &>/dev/null
  nmcli dev wifi hotspot ifname wlan1 ssid "$HOTSPOT_SSID" password "$HOTSPOT_PASS"
  echo "[✅] Hotspot \"$HOTSPOT_SSID\" active."

  start_hint_engine & hint_pid=$!

  declare -A cmap
  while true; do
    echo "⟵ Monitoring clients on $HOTSPOT_SSID ⟶"
    clients=$(arp -n | grep wlan1 | awk '{print $1":"$3}')
    idx=0

    for c in $clients; do
      ip="${c%%:*}"; mac="${c##*:}"
      name=$(avahi-resolve-address "$ip" 2>/dev/null | awk '{print $2}')
      name=${name:-UnknownDevice}
      time=$(date "+%H:%M:%S %d/%m/%Y")
      tag=$(echo {A..Z} | sed -n "$((idx+1))p")
      echo "$tag) $name : $ip @ $time"
      echo "$name : $ip @ $time" >> "$LOGFILE"
      cmap[$tag]="$ip:$mac:$name"

      if [[ -f "$ROOT/kicked/$ip.kicked" ]] ||
         [[ -f "$ROOT/wifi-blocked-users/$ip.blocked" ]] ||
         [[ -f "$ROOT/wifi-blocked-users/$mac.blocked" ]]; then

        echo "WARN: $name rejoined. D=block, E=ignore, F=block MAC"
        read -n1 r; echo
        case "$r" in
          D) touch "$ROOT/wifi-blocked-users/$ip.blocked";;
          E) echo "Ignored.";;
          F) iptables -A INPUT -m mac --mac-source "$mac" -j DROP;;
          *) echo "—";;
        esac
        handle_rejoin "$ip" "$mac" "$name"
      fi

      (( idx++ ))
    done

    echo "Actions: 2=Stop, 3=Kick, 9=Unban, P=PowerMenu"
    read -n1 a; echo
    case "$a" in
      2) echo "Stopping hotspot…"; nmcli connection down "$HOTSPOT_SSID"; kill $hint_pid; break ;;
      3)
        echo "Kick which? (A–Z):"; read -n1 k; echo
        info="${cmap[$k]}"
        [[ $info ]] && touch "$ROOT/kicked/${info%%:*}.kicked" && echo "Kicked ${info##*:}";;
      9)
        banned=( "$ROOT/wifi-blocked-users"/*.blocked )
        if [[ ${#banned[@]} -eq 0 ]]; then
          echo "All clear—no banned users."
        else
          for i in "${!banned[@]}"; do
            nm=$(grep '^Device:' "${banned[i]}" | cut -d: -f2-)
            echo "$i) ${nm}"
          done
          read -p "Unban index: " ui
          rm "${banned[ui]}"
          echo "Unbanned."
        fi;;
      P)
        # call power menu in this session
        ;;
      *)
        echo "—";;
    esac

    sleep 5
  done
  exit 0
}

#———— Wi-Fi Connect Function ———————————————————————————————————————

connect_to_wifi() {
  mkdir -p "$ROOT/wifi-passwords"
  echo "[📡] Scanning Wi-Fi..."
  mapfile -t lines < <(
    nmcli -t -f SSID,SECURITY,SIGNAL dev wifi | grep -v '^:' | sort -u
  )

  for i in "${!lines[@]}"; do
    IFS=: read -r ss sec sig <<< "${lines[i]}"
    bar=$(get_signal_bar "$sig")
    pf="$ROOT/wifi-passwords/$ss.txt"
    if [[ "$sec" == "--" || -f "$pf" ]]; then icon="🔓"; else icon="🔒"; fi
    cap=""
    is_captive && cap="(CAPTIVE)"
    printf "%2d) %s [%s %2d%%] %s %s\n" $((i+1)) "$ss" "$bar" "$sig" "$icon" "$cap"
  done

  read -p "Choose network #: " n
  sel="${lines[n-1]}"
  IFS=: read -r ss sec sig <<< "$sel"
  pf="$ROOT/wifi-passwords/$ss.txt"

  if [[ -f $pf ]]; then
    pw=$(<"$pf")
  elif [[ "$sec" != "--" ]]; then
    read -p "Password for $ss: " pw
    echo "$pw" > "$pf"
  fi

  nmcli dev wifi connect "$ss" password "$pw"
  if [[ $? -eq 0 ]]; then
    echo "Connected."
    if is_captive; then
      echo "Captive detected—launching browser..."
      open_captive_terminal
      touch "$ROOT/captive-verified/$ss.ok"
    fi
  else
    echo "Failed. Restart? (Y/n)"
    read -n1 r; [[ $r =~ [Yy] ]] && sudo reboot
  fi
}

#———— Hotspot Clone Launcher (main menu) ————————————————————————————

clone_hotspot() {
  mapfile -t nets < <(nmcli -t -f SSID dev wifi | grep -v '^$')
  echo "Available to clone:"
  for i in "${!nets[@]}"; do echo "$i) ${nets[i]}"; done
  read -p "Select #: " ci
  export SSID_TO_CLONE="${nets[ci]}"
  read -p "Password for $SSID_TO_CLONE: " CLONE_PASS
  export HOTSPOT_PASS

  lxterminal -t HOTSPOTLOGANDSHUTDOWN -e \
    bash -c "SSID_TO_CLONE='$SSID_TO_CLONE' CLONE_PASS='$CLONE_PASS' \
    HOTSPOT_PASS='$HOTSPOT_PASS' \"$0\" monitor-hotspot" &
  echo "Hotspot monitor launched in new tab."
}

#———— Power Menu ———————————————————————————————————————————————

power_menu() {
  echo "--- POWER MENU ---"
  echo " 1) Restart    2) Shutdown     3) Update"
  echo " 4) Update→1h  5) Update+Down  6) Up→1h+Down"
  echo " 7) Update+Reboot 8) Update+Logout  9) Logout"
  echo "10) Update×2  11) Update+Uninstall Pi OS"
  echo "12) Update+Uninstall→Linux  13) IBM takeover"
  read -p "Choice: " o
  case $o in
    1) sudo reboot ;;
    2) sudo shutdown now ;;
    3) sudo apt update && sudo apt upgrade -y ;;
    4) sleep 3600; sudo apt update && sudo apt upgrade -y ;;
    5) sudo apt update && sudo apt upgrade -y; sudo shutdown now ;;
    6) sleep 3600; sudo apt update && sudo apt upgrade -y; sudo shutdown now ;;
    7) sudo apt update && sudo apt upgrade -y; sudo reboot ;;
    8) sudo apt update && sudo apt upgrade -y; pkill -KILL -u "$USER" ;;
    9) pkill -KILL -u "$USER" ;;
    10) sudo apt update && sudo apt upgrade -y; sudo apt update && sudo apt upgrade -y ;;
    11) echo "[⚠️] Pi OS uninstall skipped for safety." ;;
    12) echo "[🔄] Linux install simulated…" ;;
    13)
      read -sp "Pass: " p; echo
      if [[ "$p" == "$PASSWORD_FOR_OS" ]]; then
        echo "[💾] Backing up…"
        mkdir -p ~/pi_backup_external
        cp -r /etc ~/pi_backup_external 2>/dev/null
        echo "[⚙️] Installing IBM OS… (simulated)"
      else
        echo "[⛔] Bad password."
      fi
      ;;
    *) echo "Invalid." ;;
  esac
}

#———— Main Menu Loop —————————————————————————————————————————————

while true; do
  cat <<EOF

===== Liam’s Pi-Connect Guardian =====
 1) Power Controls
 2) Connect to Wi-Fi
 3) Clone & Monitor Hotspot
 4) Exit
=====================================

EOF
  read -p "Select: " m
  case $m in
    1) power_menu ;;
    2) connect_to_wifi ;;
    3) clone_hotspot ;;
    4) echo "Bye!"; exit 0 ;;
    *) echo "Invalid." ;;
  esac
done
