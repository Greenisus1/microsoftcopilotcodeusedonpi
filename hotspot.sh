#!/bin/bash
# hotspot_clone.sh – Script to clone/extend a Wi-Fi hotspot on Raspberry Pi
# 
# This script either connects to an existing Wi-Fi network or starts a Wi-Fi hotspot (Access Point),
# effectively turning the Raspberry Pi into a Wi-Fi-to-Wi-Fi router or repeater. 
# It handles lock files to prevent multiple instances, and includes a force-start flag 
# to override locks. It also logs crashes for debugging.
#
# Usage:
#   sudo ./hotspot_clone.sh [--force] [--no-log] [--help]
# 
# Options:
#   --force   (-f) : Ignore any existing lock and force the script to run.
#   --no-log       : Disable logging to file (run quietly, except crash reports).
#   --help         : Display usage information.
#
# Requirements:
#   - Bash shell
#   - NetworkManager with nmcli (for managing Wi-Fi connections)
#   - Appropriate privileges (script likely needs to run as root to control networking)
#
# Version 2.0 – Updated to address lock file conflicts, here-doc syntax, and nmcli field issues.
#             – Added error trapping and debug logging features.
#
# ----------------------------------------------------------------------------------------

# Strict mode: exit on error, catch unset vars, and fail on pipeline errors
set -Eeuo pipefail

# Configuration Variables (adjust these as needed)
WIFI_DEV="wlan0"                        # Wi-Fi interface name to use for hotspot (e.g., built-in Wi-Fi)
HOTSPOT_SSID="PiRepeater"               # SSID for the hotspot mode (when acting as AP)
HOTSPOT_PASS="ChangeMeQuick!"           # Password for the hotspot (8+ characters, WPA2)
HOTSPOT_CHANNEL="default"              # Channel for hotspot (e.g., "6" or "auto"/"default" for auto-selection)
HOTSPOT_BAND="auto"                    # Band for hotspot: "auto", or "2.4", "5" to prefer, if device supports

# Lock file path
LOCK_FILE="/tmp/hotspot_clone.lock"

# Log file for runtime information and crash reports
LOG_FILE="/var/log/hotspot_clone.log"
ERROR_LOG="/var/log/hotspot_clone_error.log"

# Flags (default values)
FORCE_START=0
LOGGING_ENABLED=1

# Print usage information
show_usage() {
    echo "Usage: $0 [--force] [--no-log] [--help]"
    echo "  --force, -f    Bypass lock and force start even if another instance is detected."
    echo "  --no-log       Disable detailed logging to $LOG_FILE (only errors will be logged)."
    echo "  --help         Show this help message."
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE_START=1
            shift
            ;;
        --no-log)
            LOGGING_ENABLED=0
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            # Ignore non-option arguments (or handle as needed)
            shift
            ;;
    esac
done

# Logging function (writes to log file if enabled, and to stdout)
log() {
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    if (( LOGGING_ENABLED )); then
        echo "[$timestamp] $msg" | tee -a "$LOG_FILE"
    else
        echo "[$timestamp] $msg"
    fi
}

# Error reporting function for crashes (called via trap on ERR)
err_report() {
    local err_line="$1"
    local err_cmd="$2"
    local err_code="$3"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    # Log to error log file
    {
        echo "[$timestamp] ERROR: Command '${err_cmd}' failed at line ${err_line} with exit status ${err_code}."
        echo "[$timestamp] (Script will abort and clean up resources.)"
    } >> "$ERROR_LOG"
    # Also echo to stdout/stderr for immediate feedback
    >&2 echo "[$timestamp] *** Script error at line $err_line: '${err_cmd}' (exit code $err_code) ***"
}

# Cleanup function to release resources on exit
cleanup() {
    local exit_code=$?
    # Remove lock file if it exists
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        # Only log removal if logging is enabled
        (( LOGGING_ENABLED )) && echo "[Cleanup] Removed lock file $LOCK_FILE." >> "$LOG_FILE"
    fi
    # If script terminated with error, note it
    if [[ $exit_code -ne 0 ]]; then
        # Log that we are exiting due to an error
        local timestamp
        timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
        echo "[$timestamp] Script exited with error (status $exit_code). See $ERROR_LOG for details." >> "$LOG_FILE"
    fi
    exit $exit_code
}

# Set traps for ERR and EXIT
trap 'err_report ${LINENO} "$BASH_COMMAND" $?' ERR
trap 'cleanup' EXIT

# Function to initialize logging (rotate logs if needed, etc.)
init_logging() {
    if (( LOGGING_ENABLED )); then
        # Ensure log directory exists
        mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$ERROR_LOG")"
        # Optionally, rotate old logs if they grow large (not implemented here, just truncating for simplicity)
        : > "$LOG_FILE"   # truncate regular log
        : > "$ERROR_LOG"  # truncate error log
        log "=== Starting hotspot_clone script (PID $$) ==="
    fi
}

# Acquire lock to ensure single instance
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local prev_pid
        prev_pid="$(< "$LOCK_FILE")" 2>/dev/null || prev_pid=""
        if [[ -n "$prev_pid" ]]; then
            if kill -0 "$prev_pid" 2>/dev/null; then
                if (( FORCE_START == 0 )); then
                    echo "Another instance is running (PID $prev_pid). Use --force to override." >&2
                    exit 1
                else
                    echo "Warning: Another instance (PID $prev_pid) is apparently running, but proceeding due to --force." >&2
                fi
            else
                # Stale lock file
                (( LOGGING_ENABLED )) && echo "[Lock] Removing stale lock file (PID $prev_pid not running)." >> "$LOG_FILE"
            fi
        else
            (( LOGGING_ENABLED )) && echo "[Lock] Lock file present but empty, ignoring." >> "$LOG_FILE"
        fi
        # Remove the stale/empty lock file
        rm -f "$LOCK_FILE"
    fi

    # Create new lock file with this PID
    echo "$$" > "$LOCK_FILE"
    # Double-check that lock file was created
    if [[ ! -f "$LOCK_FILE" ]]; then
        echo "Failed to create lock file at $LOCK_FILE. Exiting." >&2
        exit 1
    fi
    (( LOGGING_ENABLED )) && echo "[Lock] Acquired lock with PID $$." >> "$LOG_FILE"
}

# Function to check if Pi is already connected to a Wi-Fi network (internet source)
is_connected_to_wifi() {
    # We use nmcli to see if the wifi interface has an active connection
    local active_ssid
    active_ssid=$(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status | grep "^$WIFI_DEV:" | cut -d: -f4)
    # If CONNECTION field is not empty and STATE is connected, we assume it's connected to Wi-Fi
    # (Note: This assumes $WIFI_DEV is managed by NetworkManager)
    if [[ -n "$active_ssid" && "$active_ssid" != "--" ]]; then
        return 0  # true, has active connection
    else
        return 1  # false, not connected
    fi
}

# Function to scan available Wi-Fi networks and choose a target to connect (if any)
scan_and_select_network() {
    # This function scans for Wi-Fi networks. In a real script, you might match against preferred SSIDs or conditions.
    log "Scanning for available Wi-Fi networks..."
    # Use nmcli to list networks with relevant fields
    # Fields: SSID, SECURITY, SIGNAL, FREQ
    # We will output as tabular for parsing (no header with -t terse mode)
    local scan_results
    scan_results=$(nmcli -t -f SSID,SECURITY,SIGNAL,FREQ device wifi list 2>/dev/null) || true
    # The output is lines like "MyWiFi:WPA2:75:2412"
    if [[ -z "$scan_results" ]]; then
        log "No Wi-Fi networks found in scan."
        return 1
    fi

    # As an example, pick the strongest open network (just for demonstration of selection logic)
    local best_ssid=""
    local best_signal=0
    local best_security=""
    local best_freq=""
    while IFS=':' read -r ssid sec signal freq; do
        # If no SSID (hidden network), skip
        [[ -z "$ssid" ]] && continue
        # Prefer open networks (no security) or use any available
        # Here, check if sec contains "WPA" or "WEP" or is "--"
        if [[ "$sec" == "--" ]]; then
            # Open network, no security, treat signal
            signal=${signal:-0}
            if (( signal > best_signal )); then
                best_signal=$signal
                best_ssid="$ssid"
                best_security="$sec"
                best_freq="$freq"
            fi
        else
            # If all networks are secure, we could choose the strongest secure one if we have credentials (not implemented here).
            # For now, skip secured networks in this selection example.
            :
        fi
    done <<< "$scan_results"

    if [[ -n "$best_ssid" ]]; then
        log "Selected network '$best_ssid' (Signal ${best_signal}%)."
        # Optionally, determine band from frequency for logging
        if [[ "$best_freq" -ge 3000 ]]; then
            log "Target network is on 5 GHz band (Frequency ${best_freq} MHz)."
        else
            log "Target network is on 2.4 GHz band (Frequency ${best_freq} MHz)."
        fi
        # Return the chosen SSID (global variable or echo output)
        SELECTED_SSID="$best_ssid"
        return 0
    else
        log "No suitable open network found to connect."
        return 1
    fi
}

# Function to connect to a Wi-Fi network (as a client)
connect_to_wifi() {
    local ssid="$1"
    if [[ -z "$ssid" ]]; then
        log "No SSID provided to connect_to_wifi."
        return 1
    fi
    log "Attempting to connect to Wi-Fi network: $ssid"
    # If the network is open (no passphrase)
    # Note: In a real scenario, we might need to handle known networks with saved credentials.
    nmcli device wifi connect "$ssid" ifname "$WIFI_DEV" 1>>"$LOG_FILE" 2>>"$LOG_FILE" || {
        log "Failed to connect to Wi-Fi network '$ssid'."
        return 1
    }
    log "Successfully connected to Wi-Fi network '$ssid'."
    return 0
}

# Function to start the hotspot (Access Point mode)
start_hotspot() {
    log "Starting hotspot (AP mode) on $WIFI_DEV ..."
    # If a connection named "Hotspot" already exists, we may reuse it. Otherwise, nmcli can create a hotspot.
    # Use nmcli's built-in hotspot command:
    local nm_out
    if [[ "$HOTSPOT_CHANNEL" == "default" && "$HOTSPOT_BAND" == "auto" ]]; then
        nm_out=$(nmcli device wifi hotspot ifname "$WIFI_DEV" ssid "$HOTSPOT_SSID" password "$HOTSPOT_PASS" 2>&1) || {
            log "nmcli hotspot command failed: $nm_out"
            return 1
        }
    else
        # If specific channel or band preferences are set, create a custom connection profile
        # First, delete existing Hotspot connection if present (to avoid duplicates)
        nmcli connection delete "Hotspot" &>/dev/null || true
        # Construct options for band and channel if specified
        local band_option=""
        local channel_option=""
        if [[ "$HOTSPOT_BAND" == "5" || "$HOTSPOT_BAND" == "5GHz" || "$HOTSPOT_BAND" == "a" ]]; then
            band_option="band=a"
        elif [[ "$HOTSPOT_BAND" == "2.4" || "$HOTSPOT_BAND" == "2.4GHz" || "$HOTSPOT_BAND" == "bg" ]]; then
            band_option="band=bg"
        fi
        if [[ "$HOTSPOT_CHANNEL" != "default" && "$HOTSPOT_CHANNEL" != "auto" ]]; then
            channel_option="channel=$HOTSPOT_CHANNEL"
        fi
        nm_out=$(nmcli device wifi hotspot ifname "$WIFI_DEV" ssid "$HOTSPOT_SSID" password "$HOTSPOT_PASS" $band_option $channel_option 2>&1) || {
            log "nmcli hotspot (with band/channel) failed: $nm_out"
            return 1
        }
    fi
    log "Hotspot started. SSID: $HOTSPOT_SSID  Password: $HOTSPOT_PASS"
    return 0
}

# Function to stop the hotspot (if needed) and disconnect
stop_hotspot() {
    log "Stopping hotspot on $WIFI_DEV..."
    nmcli connection down Hotspot &>/dev/null || true
    # Optionally delete the hotspot connection profile to reset settings
    nmcli connection delete Hotspot &>/dev/null || true
    log "Hotspot stopped."
}

# -----------------------------------
# Main Script Logic
# -----------------------------------
init_logging        # Initialize or reset logs
acquire_lock        # Obtain lock file (or exit if another instance is active and no --force)

# Determine action: connect to existing Wi-Fi or start hotspot
if is_connected_to_wifi; then
    log "Already connected to a Wi-Fi network. Hotspot mode not required."
    # Optionally, if already connected and hotspot is running, we might stop hotspot. 
    # For now, just exit as nothing needs to be done.
    exit 0
else
    log "Not connected to any Wi-Fi. Will try to connect as client, otherwise enable hotspot."
    if scan_and_select_network; then
        # We found a network to connect to (SSID in SELECTED_SSID)
        if connect_to_wifi "$SELECTED_SSID"; then
            log "Operating as Wi-Fi client (repeater source). Hotspot mode can be disabled."
            # If needed, ensure hotspot is off
            nmcli connection down Hotspot &>/dev/null || true
            # Script could end here, as we connected to Wi-Fi successfully.
            exit 0
        fi
    fi
    # If we reach here, either no network was chosen or connection failed. Enable hotspot as fallback.
    if start_hotspot; then
        log "Hotspot active. Clients can connect to SSID '$HOTSPOT_SSID'."
        # At this point, the Pi is an AP. If internet sharing is needed (e.g., via another interface like eth0),
        # that configuration would be done here (for example, enable IP forwarding, DNS/DHCP via dnsmasq, etc.).
        # NetworkManager's "hotspot" sets up a shared connection if another uplink is available (Ethernet).
        :
    else
        log "Failed to start hotspot. No network connectivity available."
        # Still consider exiting with error code, which will trigger error trap logging as well.
        exit 1
    fi
fi

# End of main logic. The script will continue running (if hotspot is up, it might just wait or do periodic checks).
# In this example, we’ll just sleep to keep the script active, simulating a service that monitors connections.
while true; do
    sleep 60
    # In a real script, you might periodically check if the upstream network appears and then switch modes, etc.
    # For demonstration, we'll break after some interval or condition. Here, just run indefinitely unless externally stopped.
done

# (The trap on EXIT will handle cleanup when the script is terminated.)
