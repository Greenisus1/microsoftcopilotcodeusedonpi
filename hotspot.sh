#!/bin/bash
#   _   _    ___  ____   ____         ___     _                 
#  | | | |  / _ \|  _ \ / ___|  ___  / _ \   / \   ___ ___ ___  
#  | |_| | | | | | |_) | |  _  / _ \| | | | / _ \ / __/ __/ _ \ 
#  |  _  | | |_| |  __/| |_| | (_) | |_| |/ ___ \ (_| (_|  __/ 
#  |_| |_|  \___/|_|    \____|\___/ \___//_/   \_\___\___\___| 
#  
#  Raspberry Pi Wi-Fi Hotspot Clone Script
#  Version 1.0
#
#  This script connects to a specified Wi-Fi network and clones it as a wireless hotspot (access point).
#  It ensures only one instance runs at a time (using a lock file), can bypass the lock with a force flag,
#  and generates a crash report if any error occurs during execution.
#
#  Usage: sudo ./hotspot_clone.sh [--force-start] [--ssid <name>] [--pass <password>] [--help]
#    --force-start   Bypass the lock file check and force the hotspot to start (use with caution).
#    --ssid <name>   SSID of the Wi-Fi network to clone (overrides the default TARGET_SSID configured below).
#    --pass <pass>   Password for the Wi-Fi network to clone (overrides the default TARGET_PASS configured below).
#    --help          Show this help message and exit.
#
#  Ensure you run this script as root (sudo) since it requires network configuration privileges.
#  The script will:
#    - Acquire a lock to prevent multiple instances.
#    - Optionally bypass the lock if --force-start is given.
#    - Scan for the target Wi-Fi network and get its channel (and determine band).
#    - Connect the Raspberry Pi to the target Wi-Fi network as a client.
#    - Start a Wi-Fi hotspot (access point) on the Raspberry Pi with the same SSID and password (cloning the network).
#    - The hotspot will operate on the same channel and band as the target network to allow simultaneous use of one Wi-Fi interface.
#    - Enable internet sharing (NAT) from the Pi's Wi-Fi client connection to the hotspot.
#    - Generate a crash log at /tmp/hotspot_crash.log if any errors occur, for debugging.
#    - Clean up the lock file on exit.
#
#  Note: The target Wi-Fi network (to be cloned) should be in range, and the Pi must have the correct password to connect to it.
#        The Wi-Fi adapter must support AP mode (most Raspberry Pi onboard Wi-Fi do) and possibly concurrent AP+client operation.
#        If the Pi cannot operate as client and AP simultaneously, this script will not work properly.
#        It is assumed that NetworkManager is installed and managing the network interfaces (default on Raspberry Pi OS Bullseye/Bookworm).
#        If NetworkManager is not used, some nmcli commands may not function as expected.
#
#  -- Begin Script --

# Settings (defaults)
TARGET_SSID="YourHotspotSSID"    # SSID of the Wi-Fi network to clone
TARGET_PASS="YourHotspotPassword"  # Password of the Wi-Fi network to clone
WLAN_IFACE="wlan0"              # Wi-Fi interface to use for connecting and hotspot (usually wlan0 on RPi)
LOCK_FILE="/var/run/hotspot_clone.lock"  # Lock file to prevent simultaneous runs
CRASH_LOG="/tmp/hotspot_crash.log"       # Crash report log file

# Flags
FORCE_START=0

# Function: Display help/usage information
show_help() {
  echo "Usage: $0 [--force-start] [--ssid <name>] [--pass <password>] [--help]"
  echo "  --force-start   Bypass the lock file check and force start the hotspot."
  echo "  --ssid <name>   SSID of the Wi-Fi network to clone (overrides default)."
  echo "  --pass <pass>   Password of the Wi-Fi network to clone (overrides default)."
  echo "  --help          Show this help message."
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-start|-f|--force)
      FORCE_START=1
      shift
      ;;
    --ssid|-s)
      if [[ -n "$2" ]]; then
        TARGET_SSID="$2"
        shift 2
      else
        echo "Error: --ssid requires an argument." >&2
        exit 1
      fi
      ;;
    --pass|--password|-p)
      if [[ -n "$2" ]]; then
        TARGET_PASS="$2"
        shift 2
      else
        echo "Error: --pass requires an argument." >&2
        exit 1
      fi
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo "Error: Unknown option '$1'" >&2
      show_help
      exit 1
      ;;
  esac
done

# Crash report handler: this trap will capture any command errors and log diagnostic info.
trap '{
    exit_code=$?;
    # Only log if an error (non-zero exit) occurred
    if [[ $exit_code -ne 0 ]]; then
      # Append error details to crash log
      echo "[$(date)] ERROR: Command \"${BASH_COMMAND}\" failed with exit code $exit_code at line $LINENO." >> "$CRASH_LOG"
      echo "Script terminated unexpectedly. See $CRASH_LOG for details." >&2
    fi
  }' ERR

# Ensure the script exits on error and catches pipe failures
set -o errexit -o errtrace -o pipefail

# Cleanup function to remove lock file (to be called on normal exit or interruption)
cleanup() {
  # Remove lock file if it exists and was created by this process
  if [[ -n "$LOCK_FILE" && -f "$LOCK_FILE" ]]; then
    local lock_pid
    lock_pid="$(cat "$LOCK_FILE" 2>/dev/null)" || lock_pid=""
    if [[ "$lock_pid" == "$$" ]]; then
      rm -f "$LOCK_FILE"
    fi
  fi
}
# Set trap to call cleanup on script exit, and on Ctrl+C or termination signals
trap cleanup EXIT
trap cleanup SIGINT SIGTERM

# Acquire lock to prevent multiple instances
if [[ -f "$LOCK_FILE" ]]; then
  # Lock file exists, check if process is alive
  if read -r lockpid < "$LOCK_FILE"; then
    if ps -p "$lockpid" > /dev/null 2>&1; then
      # Another instance is running
      if (( FORCE_START == 1 )); then
        echo "Warning: Another instance (PID $lockpid) is indicated by lock file. Forcing start due to --force-start..." >&2
      else
        echo "Error: Another instance of this script is already running (PID $lockpid). Use --force-start to override." >&2
        exit 1
      fi
    else
      # Stale lock (process not running)
      echo "Notice: Removing stale lock file (process $lockpid not running)." >&2
      rm -f "$LOCK_FILE"
    fi
  else
    # Could not read lock file, remove it
    rm -f "$LOCK_FILE"
  fi
fi

# Create a new lock file with current PID
echo $$ > "$LOCK_FILE" || { echo "Error: Unable to create lock file at $LOCK_FILE." >&2; exit 1; }

# At this point, we have the lock (or forced start ignoring existing lock)

# Optional: trigger a fresh Wi-Fi scan to ensure up-to-date results
echo "Scanning for Wi-Fi networks..." 
nmcli device wifi rescan >/dev/null 2>&1 || true  # not critical if rescan fails (may need sudo if not root, but script is run as root)

# Find the target network from scan results
echo "Looking for target network SSID: '$TARGET_SSID'"
# We will parse the nmcli output to get channel (and possibly band).
# Use nmcli in terse mode to get SSID,CHAN fields for easier parsing.
network_line="$(nmcli -t -f SSID,CHAN device wifi list | grep -F -m1 "${TARGET_SSID}")" || network_line=""
if [[ -z "$network_line" ]]; then
  echo "Error: Target network '$TARGET_SSID' not found in scan results. Ensure it is in range and broadcasting." >&2
  exit 1
fi

# Parse the retrieved line. It should be in format "SSID:CHAN" (terse mode with -t uses ":" as delimiter).
IFS=':' read -r found_ssid found_chan <<< "$network_line"
# (Note: If SSID itself contains a colon, this parsing could break. In such a case, using a different delimiter or a more robust parsing method would be needed.)

# Double-check we got the correct SSID (in case of partial match). We'll ensure case-sensitive match.
if [[ "$found_ssid" != "$TARGET_SSID" ]]; then
  echo "Warning: Found SSID '$found_ssid' does not exactly match target '$TARGET_SSID'. Using it anyway." >&2
  # (If multiple networks share similar names, this might pick the wrong one. Ideally, ensure unique SSID.)
fi

# Channel number from scan:
CHANNEL="$found_chan"
if [[ -z "$CHANNEL" ]]; then
  echo "Error: Could not determine channel for SSID '$TARGET_SSID'." >&2
  exit 1
fi

# Determine Wi-Fi band based on channel number for AP configuration:
# Channels 1-14 are 2.4GHz (band "bg"), channels >= 36 are 5GHz (band "a").
if [[ "$CHANNEL" -le 14 ]]; then
  BAND="bg"
else
  BAND="a"
fi

echo "Found network '$found_ssid' on channel $CHANNEL (band $BAND)."

# Connect to the target Wi-Fi network as a client (using NetworkManager via nmcli).
echo "Connecting Raspberry Pi to Wi-Fi network '$TARGET_SSID'..."
# If the network is already configured in NetworkManager (with same SSID), nmcli will use existing settings if possible.
# We supply the password in case it's a new connection or to ensure correct credentials.
nmcli device wifi connect "$TARGET_SSID" password "$TARGET_PASS" ifname "$WLAN_IFACE" >/dev/null 2>&1 && \
  echo "Successfully connected to '$TARGET_SSID'." || {
    echo "Error: Failed to connect to Wi-Fi network '$TARGET_SSID'. Check the password or network availability." >&2
    # If connection fails, we should exit (the ERR trap will log details to crash log).
    exit 1
}

# Wait for a valid IP address on the Wi-Fi interface (to ensure internet connectivity is up).
echo "Obtaining IP address for the Wi-Fi connection..."
# We poll nmcli for IP; alternative is to use a short sleep or check /dhclient, but we'll use nmcli connection status.
# Timeout after ~15 seconds if not obtained.
for i in {1..15}; do
  # Check if the interface has IP (ip addr show could be used, or nmcli -f IP4.ADDRESS device show)
  ip_addr=$(nmcli -g IP4.ADDRESS device show "$WLAN_IFACE" 2>/dev/null | head -n1)
  if [[ -n "$ip_addr" ]]; then
    break
  fi
  sleep 1
done
if [[ -z "$ip_addr" ]]; then
  echo "Warning: IP address not obtained for $WLAN_IFACE after 15s. Continuing anyway." >&2
else
  echo "Assigned IP: $ip_addr"
fi

# Configure and start the Wi-Fi hotspot (AP) on the same interface using NetworkManager.
AP_CON_NAME="HotspotClone"  # Name for the hotspot connection profile
echo "Setting up hotspot (AP) with SSID '$TARGET_SSID'..."
# Remove any existing AP connection with same name if present, to avoid conflicts.
nmcli connection delete "$AP_CON_NAME" >/dev/null 2>&1 || true

# Add a new Wi-Fi connection for AP mode.
nmcli connection add type wifi ifname "$WLAN_IFACE" mode ap con-name "$AP_CON_NAME" autoconnect no ssid "$TARGET_SSID"

# Set the Wi-Fi band and channel for the AP
nmcli connection modify "$AP_CON_NAME" 802-11-wireless.band "$BAND" 802-11-wireless.channel "$CHANNEL"

# Use the same security (WPA2-PSK by default) and passphrase as the target network to truly clone credentials.
nmcli connection modify "$AP_CON_NAME" 802-11-wireless.security key-mgmt wpa-psk
nmcli connection modify "$AP_CON_NAME" wifi-sec.psk "$TARGET_PASS"

# Enable IPv4 sharing (this sets up DHCP and NAT for clients connecting to the AP).
nmcli connection modify "$AP_CON_NAME" ipv4.method shared
# (NetworkManager will assign a subnet (usually 10.42.x.0/24) for the hotspot and NAT traffic to the other interface.)

# Bring up the hotspot connection.
if nmcli connection up "$AP_CON_NAME" >/dev/null 2>&1; then
  echo "Hotspot '$TARGET_SSID' is now active on channel $CHANNEL ($BAND band)."
else
  echo "Error: Failed to start hotspot. The Wi-Fi interface may not support concurrent AP mode, or another issue occurred." >&2
  exit 1
fi

echo "Wi-Fi Hotspot clone setup complete. Clients can now connect to '$TARGET_SSID' through this Raspberry Pi."

# Script completed successfully. The cleanup trap will remove the lock file.
