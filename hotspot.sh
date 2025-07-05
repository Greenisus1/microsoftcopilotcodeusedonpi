#!/usr/bin/env bash
# mega-hotspot-monster.sh — ~600 lines of Pi Wi-Fi cloning, fallback, CLI, admin, logging, 5G support, rescue nets, iptables, etc.

################################################################################
# GLOBAL CONFIG & STATE
################################################################################
PIN_FILE="$HOME/.mega_hotspot_pin"
ADMIN_MODE=false
ROLE="usr"
CURRENT_NETWORK="CLONEROOT"
LOG_DIR="$HOME/mega_hotspot_logs"
BANNED_IPS="$LOG_DIR/banned_ips.txt"
BANNED_MACS="$LOG_DIR/banned_macs.txt"
BLOCKED_IPS_LIST=()
BLOCKED_MACS_LIST=()
CLIENT_LIST=()
UPSTREAM_IF=""
HOTSPOT_IF=""
HOTSPOT_CONN_NAME="$CURRENT_NETWORK"
HOTSPOT_SSID="${CURRENT_NETWORK}"
RESCUE_SSID="RESCUE-NET"
RESCUE_PASS="rescue-pass-123"
LEMONTST="$HOME/lemontest.sh"
LOCKFILE="/var/lock/mega-hotspot.lock"
MAX_PIN_FAIL=3

# Ensure log directory exists
mkdir -p "$LOG_DIR"/{daily,clients,errors}

################################################################################
# UTILITY FUNCTIONS
################################################################################

log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[$ts] [$level] $msg" | tee -a "$LOG_DIR/daily/$(date +%F).log"
}

error() {
  echo -e "\e[31mERROR: $*\e[0m"
  log "ERROR" "$*"
}

info() {
  echo -e "\e[32m$*\e[0m"
  log "INFO" "$*"
}

die() {
  error "$*"
  cleanup
  exit 1
}

cleanup() {
  log "INFO" "Cleaning up hotspot and connections..."
  nmcli connection down "$HOTSPOT_CONN_NAME" &>/dev/null
  rm -f "$LOCKFILE"
  info "Cleanup complete."
}

# Trap Ctrl-C and EXIT
trap cleanup EXIT
trap 'die "Interrupted by user"' INT

################################################################################
# SINGLETON LOCK
################################################################################
if ! mkdir "$LOCKFILE" 2>/dev/null; then
  die "Another instance is running. Exiting."
fi

################################################################################
# PIN & ADMIN HANDLING
################################################################################

init_pin() {
  if [[ ! -f "$PIN_FILE" ]]; then
    echo -n "🔐 Create a 4-digit admin PIN: "
    read -r newpin
    [[ "$newpin" =~ ^[0-9]{4}$ ]] || die "PIN must be exactly 4 digits."
    echo "$newpin" > "$PIN_FILE"
    chmod 600 "$PIN_FILE"
    info "Admin PIN created."
  fi
}

load_pin() {
  PIN="$(<"$PIN_FILE")"
}

prompt_pin() {
  local tries=0
  while (( tries < MAX_PIN_FAIL )); do
    echo -n "🔑 Enter PIN: "
    read -r attempt
    if [[ "$attempt" == "$PIN" ]]; then
      info "Admin mode enabled."
      ADMIN_MODE=true; ROLE="admin"
      return 0
    else
      ((tries++))
      error "Invalid PIN (attempt $tries/$MAX_PIN_FAIL)"
    fi
  done
  local decoy1 decoy2
  decoy1=$(shuf -i1000-9999 -n1); decoy2=$(shuf -i1000-9999 -n1)
  echo "the pin was($PIN,$decoy1,$decoy2)"
  die "SHUTDOWN ENGAGED due to repeated invalid PIN."
}

################################################################################
# PROMPT RENDERER
################################################################################

render_prompt() {
  echo -n "$ROLE/$CURRENT_NETWORK ~$ "
}

################################################################################
# BAND SCANNING & SELECTION
################################################################################

scan_band() {
  local band="$1" ; # "bg" or "a"
  nmcli -t -f SSID,BAND dev wifi \
    | awk -F: -v band="$band" '$2==band {print $1}' \
    | grep -v '^$'
}

select_upstream() {
  declare -a nets2g nets5g allnets
  mapfile -t nets2g < <(scan_band bg)
  mapfile -t nets5g < <(scan_band a)
  echo -e "\n📶 2.4 GHz Networks:"
  for i in "${!nets2g[@]}"; do echo "  $i) ${nets2g[$i]}"; done
  echo -e "\n📡 5 GHz Networks:"
  for i in "${!nets5g[@]}"; do echo "  $((i+${#nets2g[@]}))) ${nets5g[$i]}"; done

  allnets=("${nets2g[@]}" "${nets5g[@]}")
  echo -n "selected → "
  read -r idx
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 0 || idx >= ${#allnets[@]} )); then
    error "invalid option"; select_upstream; return
  fi
  UPSTREAM_SSID="${allnets[$idx]}"
  # Determine band interface for SSID
  UPSTREAM_IF=$(nmcli -t -f DEVICE,SSID,BAND dev wifi | grep ":$UPSTREAM_SSID:$( [[ $idx -ge ${#nets2g[@]} ]] && echo a || echo bg )" | cut -d: -f1 | head -n1)
  [[ -n "$UPSTREAM_IF" ]] || die "Cannot detect interface for $UPSTREAM_SSID"
  info "Selected upstream SSID '$UPSTREAM_SSID' on interface $UPSTREAM_IF"
}

connect_upstream() {
  local tries=0
  while (( tries < 3 )); do
    echo -n "Enter password for '$UPSTREAM_SSID': "
    read -rs upass; echo
    if nmcli dev wifi connect "$UPSTREAM_SSID" password "$upass" ifname "$UPSTREAM_IF"; then
      info "Connected to upstream '$UPSTREAM_SSID'."
      return 0
    else
      ((tries++)); error "Connection failed (attempt $tries/3)."
    fi
  done
  error "Falling back to rescue network '$RESCUE_SSID'..."
  nmcli dev wifi connect "$RESCUE_SSID" password "$RESCUE_PASS" &>/dev/null || die "Rescue network unreachable."
  info "Connected to rescue network."
}

################################################################################
# HOTSPOT CREATION & MONITORING
################################################################################

setup_hotspot() {
  # Pick same band as upstream, else fallback
  HOTSPOT_IF="$UPSTREAM_IF"
  nmcli connection delete "$HOTSPOT_CONN_NAME" &>/dev/null || true
  nmcli connection add type wifi ifname "$HOTSPOT_IF" con-name "$HOTSPOT_CONN_NAME" autoconnect yes ssid "$HOTSPOT_SSID"
  nmcli connection modify "$HOTSPOT_CONN_NAME" 802-11-wireless.mode ap 802-11-wireless.band "$(nmcli -t -f BAND dev wifi | grep -m1 "$HOTSPOT_IF" | cut -d: -f2)" ipv4.method shared
  echo -n "Set hotspot password (8–63 chars): "
  read -rs hpass; echo
  [[ ${#hpass} -ge 8 && ${#hpass} -le 63 ]] || die "Invalid WPA2 passphrase length."
  nmcli connection modify "$HOTSPOT_CONN_NAME" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$hpass"
  nmcli connection up "$HOTSPOT_CONN_NAME" || die "Failed to bring up hotspot."
  info "Hotspot '$HOTSPOT_SSID' live on $HOTSPOT_IF."
}

monitor_clients() {
  while true; do
    sleep 10
    mapfile -t CLIENT_LIST < <(arp -n | awk -v iface="$HOTSPOT_IF" '$0~iface {print $1":"$3}')
    echo
    echo "🔎 Connected clients:"
    if (( ${#CLIENT_LIST[@]} )); then
      for i in "${!CLIENT_LIST[@]}"; do
        echo "  $i) ${CLIENT_LIST[$i]}"
      done
    else
      echo "  [none]"
    fi
    echo -n "selected → "
    read -r sel
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 0 || sel >= ${#CLIENT_LIST[@]} )); then
      error "invalid option"
      continue
    fi
    IFS=: read -r cip cmac <<<"${CLIENT_LIST[$sel]}"
    echo "  Actions: 1) disconnect  2) block IP  3) ban IP+MAC  0) back"
    echo -n "selected → "; read -r action
    case "$action" in
      1) iptables -D INPUT -s "$cip" -j DROP 2>/dev/null; echo "Disconnected $cip";;
      2) iptables -A INPUT -s "$cip" -j DROP; echo "$cip blocked";;
      3)
        iptables -A INPUT -s "$cip" -j DROP
        iptables -A INPUT -m mac --mac-source "$cmac" -j DROP
        echo "$cip" >>"$BANNED_IPS"
        echo "$cmac" >>"$BANNED_MACS"
        echo "$cip & $cmac banned"
        ;;
      0) ;;
      *) error "invalid option" ;;
    esac
  done
}

################################################################################
# NETWORK STATUS
################################################################################

network_status() {
  if [[ -x "$LEMONTST" ]]; then
    echo "🧪 Running speed test..."
    bash "$LEMONTST" | tee -a "$LOG_DIR/daily/$(date +%F).log"
  else
    error "Speedtest script not found at $LEMONTST"
  fi
}

################################################################################
# COMMAND DISPATCHER
################################################################################

show_help() {
  cat <<-EOF
  Available commands:
    network.shutdown       – stop hotspot + exit (admin only)
    network.status         – run speedtest (lemontest.sh)
    network.users          – list & manage clients (admin only)
    admin.sudo             – enable admin mode for one command
    admin.sudo set true    – stay in admin mode
    admin.sudo set false   – drop to user mode
    enableadmin [pin]      – same as admin.sudo
    disableadmin [pin]     – exit admin mode
    newterminal            – open a new bash session
    code.bash [bashcode]   – run inline bash
    unban [IP]             – remove IP ban
    credits                – show credits
    help                   – this help text
  EOF
}

dispatch_cmd() {
  local cmd="$1"
  case "$cmd" in
    network.shutdown* ) network_shutdown "$cmd" ;;
    network.status    ) network_status ;;
    network.users     ) list_users ;;
    admin.sudo        ) prompt_pin ;;
    "admin.sudo set true"  ) prompt_pin ;;
    "admin.sudo set false" ) ADMIN_MODE=false; ROLE="usr"; info "Admin mode turned off." ;;
    enableadmin*      ) prompt_pin ;;
    disableadmin*     ) disable_admin ;;
    newterminal       ) lxterminal & ;;
    code.bash*        ) bash -c "${cmd#code.bash }" ;;
    unban*            )
      local ip="${cmd#unban }"
      sed -i "/$ip/d" "$BANNED_IPS"
      iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
      info "Unbanned $ip"
      ;;
    credits           ) echo "hi there greenisus1 made this silly" ;;
    help              ) show_help ;;
    *                 ) error "invalid cmd"; show_help ;;
  esac
}

################################################################################
# MAIN LOOP
################################################################################

init_pin
load_pin

info "Starting mega-hotspot-monster..."
select_upstream
connect_upstream
setup_hotspot

info "Entering interactive terminal. Type 'help' for commands."

while true; do
  render_prompt
  read -r line || break
  dispatch_cmd "$line"
done

cleanup
exit 0
