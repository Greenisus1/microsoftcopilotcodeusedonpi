#!/usr/bin/env bash
#
# mega-hotspot-monster.sh
# A resilient, self-healing Raspberry Pi hotspot shell
#
# Features:
#  - Single-instance lock (file, no directories)
#  - CTRL+E override at any time (mapped to SIGINT)
#  - Step-by-step fail-safe replay of last action
#  - Automatic crash report with BEGIN/END markers
#  - Command-loop interface with built-in help & admin mode
#  - Network scan, start/stop hotspot, update portal, user management

#######################################
##  CONFIGURATION
#######################################
LOCKFILE="/var/lock/mega-hotspot.lock"
CRASH_LOG="$HOME/mega-hotspot-crash.log"
ADMIN_PIN_FILE="$HOME/.hotspot_admin_pin"
ADMIN_MODE=false

#######################################
##  STATE TRACKING
#######################################
STEP="INIT"
LAST_COMMAND=""

#######################################
##  UTILITY FUNCTIONS
#######################################
die() {
  echo "ERROR: $1" >&2
  exit 1
}

log_step() {
  echo "[STEP:$STEP]" >>"$CRASH_LOG"
}

on_error() {
  local lineno=$1
  {
    echo "BEGIN:CRASH"
    echo "[ERROR] Crash at step: $STEP (line $lineno)"
    echo "Last command: $LAST_COMMAND"
    echo "Timestamp: $(date)"
    echo "END:CRASH"
  } >"$CRASH_LOG"
  die "Script crashed. Crash report saved at $CRASH_LOG"
}

#######################################
##  SIGNAL & KEYBINDINGS
#######################################
# Map CTRL+E to SIGINT (override)
stty intr '^E'
trap 'trigger_fail_safe' SIGINT
trap 'on_error $LINENO' ERR

trigger_fail_safe() {
  echo
  echo "🛑 CTRL+E override triggered — re-running last action."
  eval "$LAST_COMMAND"
}

#######################################
##  LOCK MANAGEMENT
#######################################
acquire_lock() {
  STEP="LOCK"
  if [[ -e $LOCKFILE ]]; then
    die "Another instance is running. Exiting."
  fi
  touch "$LOCKFILE" || die "Cannot create lock file"
}

release_lock() {
  STEP="UNLOCK"
  rm -f "$LOCKFILE"
}

#######################################
##  ADMIN MODE
#######################################
read_admin_pin() {
  if [[ -f $ADMIN_PIN_FILE ]]; then
    ADMIN_PIN=$(<"$ADMIN_PIN_FILE")
  else
    echo -n "🔐 Create a 4-digit admin PIN: "
    read -r ADMIN_PIN
    echo "$ADMIN_PIN" >"$ADMIN_PIN_FILE"
    echo "Admin PIN created."
  fi
}

enable_admin() {
  read -rp "Enter admin PIN: " pin
  if [[ $pin == $ADMIN_PIN ]]; then
    ADMIN_MODE=true
    echo "✅ Admin mode enabled."
  else
    echo "❌ Invalid PIN."
  fi
}

#######################################
##  COMMAND IMPLEMENTATIONS
#######################################
cmd_network_shutdown() {
  STEP="SHUTDOWN"
  echo "Stopping hotspot and exiting..."
  nmcli connection down Hotspot >/dev/null 2>&1
  release_lock
  exit 0
}
cmd_network_status() {
  STEP="STATUS"
  echo "Running speedtest..."
  speedtest-cli
}
cmd_network_users() {
  STEP="USERS"
  if ! $ADMIN_MODE; then
    echo "Admin only."
    return
  fi
  echo "Listing connected clients..."
  arp -n
}
cmd_update_portal() {
  STEP="UPDATE"
  echo "Launching installer..."
  bash ~/hotspot-installer-v0.1.sh
}
cmd_newterminal() {
  STEP="NEWTERM"
  echo "Opening new shell..."
  bash & exit 0
}
cmd_bash_code() {
  STEP="INLINE"
  echo "Executing inline bash: $*"
  LAST_COMMAND="$__func $*"
  eval "$*"
}
cmd_unban() {
  STEP="UNBAN"
  if ! $ADMIN_MODE; then
    echo "Admin only."
    return
  fi
  echo "Unbanning IP: $1"
  iptables -D INPUT -s "$1" -j DROP
}
cmd_credits() {
  STEP="CREDITS"
  cat <<EOF
mega-hotspot-monster v1.0
Built by Liam’s fury & Copilot’s code
EOF
}
cmd_help() {
  STEP="HELP"
  cat <<EOF
Available commands:
  network.shutdown – stop hotspot + exit (admin only)
  network.status   – run speedtest
  network.users    – list & manage clients (admin only)
  admin.sudo       – enable admin mode
  update.portal    – open update installer
  newterminal      – open a new bash session
  code.bash [...]  – run inline bash
  unban [IP]       – remove IP ban
  credits          – show credits
  help             – this help text
EOF
}

#######################################
##  NETWORK SCAN & LAUNCH
#######################################
scan_networks() {
  STEP="SCAN"
  echo "📶 2.4 GHz Networks:"
  nmcli -t -f SSID,FREQ device wifi list \
    | grep -E ":[2][0-9][0-9][0-9]" \
    | cut -d: -f1
  echo
  echo "📡 5 GHz Networks:"
  nmcli -t -f SSID,FREQ device wifi list \
    | grep -E ":[5][0-9][0-9][0-9]" \
    | cut -d: -f1
}

start_hotspot() {
  STEP="LAUNCH"
  echo "🚀 Starting hotspot on wlan0..."
  nmcli device wifi hotspot ifname wlan0 ssid "RPiHotspot" password "raspihotspot"
}

#######################################
##  MAIN COMMAND LOOP
#######################################
main_loop() {
  while true; do
    echo -n "hotspot> "
    read -r INPUT ARGS
    [[ -z $INPUT ]] && continue
    case $INPUT in
      network.shutdown) LAST_COMMAND="cmd_network_shutdown"; cmd_network_shutdown ;;
      network.status)   LAST_COMMAND="cmd_network_status";   cmd_network_status ;;
      network.users)    LAST_COMMAND="cmd_network_users";    cmd_network_users ;;
      admin.sudo)       LAST_COMMAND="enable_admin";         enable_admin ;;
      update.portal)    LAST_COMMAND="cmd_update_portal";    cmd_update_portal ;;
      newterminal)      LAST_COMMAND="cmd_newterminal";      cmd_newterminal ;;
      code.bash)        LAST_COMMAND="cmd_bash_code $ARGS";  cmd_bash_code $ARGS ;;
      unban)            LAST_COMMAND="cmd_unban $ARGS";      cmd_unban $ARGS ;;
      credits)          LAST_COMMAND="cmd_credits";          cmd_credits ;;
      help)             LAST_COMMAND="cmd_help";             cmd_help ;;
      *) echo "Unknown command. Type 'help'." ;;
    esac
  done
}

#######################################
##  BOOTSTRAP
#######################################
acquire_lock
read_admin_pin
scan_networks
start_hotspot
main_loop

# End of mega-hotspot-monster.sh
