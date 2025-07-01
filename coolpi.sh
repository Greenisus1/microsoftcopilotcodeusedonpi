#!/bin/bash
# CoolPi - All-in-One Raspberry Pi Management Script
# This script provides a menu-driven interface for system utilities, file management,
# app installation (App Store), GUI app launching, and includes self-update capability.
# It is designed for Raspberry Pi OS and uses standard commands (apt, curl, etc.).
# 
# Note: Run this script in a terminal. For full functionality, ensure you have an 
# internet connection (for updates and GitHub publishing) and are in a graphical 
# session when launching GUI apps.

# --- Configuration and Global Variables ---
SCRIPT_URL="https://your-repo-or-url/coolpi.sh"  # URL to fetch latest script version for self-update
SCRIPT_PATH="$(realpath "$0")"
VERSION="1.0.0"  # Script version

# Colors for output (optional, using plain text for simplicity)
# e.g., GREEN='\e[32m'; RED='\e[31m'; NC='\e[0m'

# --- Self-Update Function ---
update_script() {
    # This function checks for a newer version of this script and updates it if available.
    echo "Checking for script updates..."
    # Fetch the latest script from the defined URL
    if command -v curl >/dev/null 2>&1; then
        curl -sfL "$SCRIPT_URL" -o /tmp/coolpi_update.sh
    else
        echo "Error: 'curl' is not installed. Cannot check for updates."
        return 1
    fi
    if [ ! -s /tmp/coolpi_update.sh ]; then
        echo "No update found (or failed to download update)."
        rm -f /tmp/coolpi_update.sh
        return 1
    fi
    # Optionally compare version numbers (not implemented; always update if file is fetched)
    # You could source /tmp/coolpi_update.sh and compare VERSION variables if maintained.
    echo "Update found! Applying update..."
    # Replace current script file with the new one
    cp -f /tmp/coolpi_update.sh "$SCRIPT_PATH" && chmod +x "$SCRIPT_PATH"
    rm -f /tmp/coolpi_update.sh
    echo "CoolPi script has been updated. Restarting..."
    exec "$SCRIPT_PATH" "$@"   # Re-run the script with same arguments (if any)
}

# --- Symlink Setup Function ---
ensure_symlink() {
    # Create or update symlink /usr/local/bin/update-coolpi pointing to this script for quick updates
    local link="/usr/local/bin/update-coolpi"
    # Only attempt if we have write permission or using sudo
    if [ "$(readlink -f "$link")" != "$SCRIPT_PATH" ]; then
        sudo ln -sf "$SCRIPT_PATH" "$link" >/dev/null 2>&1 || return 0
    fi
}

# --- System Utilities Functions ---
show_storage_info() {
    # Display detailed storage usage and a visual meter for root filesystem
    echo "Storage Usage:"
    df -h /                    # show human-readable usage for root (/)
    # Calculate visual meter for root filesystem usage
    local used_pct=$(df -P / | awk 'NR==2 {print $5}' | sed 's/%//')
    local size=$(df -h / | awk 'NR==2 {print $2}')
    # Build usage bar (20 blocks)
    local blocks=$((used_pct/5))
    ((blocks > 20)) && blocks=20
    local bar=""
    for ((i=0; i<20; i++)); do
        if [ $i -lt $blocks ]; then bar+="#"; else bar+="-"; fi
    done
    echo "Root disk: [${bar}] ${used_pct}% of ${size} used"
}

open_shell() {
    # Opens an interactive shell. User can type 'exit' to return.
    echo "Opening an interactive shell. Type 'exit' to return to CoolPi."
    bash
}

system_menu() {
    # System utilities submenu for reboot, shutdown, etc.
    local choice
    while true; do
        echo ""
        echo "==== System Utilities ===="
        echo "1) Reboot Raspberry Pi"
        echo "2) Shutdown Raspberry Pi"
        echo "3) Storage Info"
        echo "4) Open Terminal Shell"
        echo "5) Run raspi-config"
        echo "0) Back to Main Menu"
        read -rp "Choose an option: " choice
        case "$choice" in
            1)  # Reboot
                read -rp "Are you sure you want to reboot? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy] ]]; then
                    echo "Rebooting now..."
                    sudo reboot
                    exit 0  # in case reboot command fails, exit script
                fi
                ;;
            2)  # Shutdown
                read -rp "Are you sure you want to shutdown? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy] ]]; then
                    echo "Shutting down now..."
                    sudo poweroff
                    exit 0
                fi
                ;;
            3)  # Storage view
                show_storage_info
                read -rp "Press Enter to return to menu..." dummy
                ;;
            4)  # Embedded shell
                open_shell
                # When user exits shell, continue
                ;;
            5)  # Run raspi-config (requires sudo)
                sudo raspi-config
                echo "Exited raspi-config. Returning to menu..."
                ;;
            0) 
                # Back to main menu
                break
                ;;
            *) 
                echo "Invalid selection. Please enter a number from the menu."
                ;;
        esac
    done
}

# --- File Manager Function ---
file_manager() {
    # Basic file navigation and file operations (run, publish, delete).
    local start_dir="$PWD"
    local choice file selection
    while true; do
        echo ""
        echo "==== File Manager (current directory: $PWD) ===="
        # List directories and files in current directory
        local entries=()
        # If not at root, provide parent directory option
        if [ "$PWD" != "/" ]; then
            entries+=("..") 
        fi
        # Gather directory contents (excluding . and ..)
        local item
        while IFS= read -r item; do
            entries+=("$item")
        done < <(ls -A)  # List all except . and .. (sorted alphabetically by default)
        # Print numbered list
        local idx=1
        for item in "${entries[@]}"; do
            # Mark directories with a slash for clarity
            [ -d "$item" ] && printf "%2d) %s/\n" "$idx" "$item" || printf "%2d) %s\n" "$idx" "$item"
            idx=$((idx+1))
        done
        echo " 0) Back to Main Menu"
        # Read user choice
        read -rp "Choose a file or directory: " choice
        if [[ "$choice" == "0" ]]; then
            # Exit file manager
            break
        fi
        # Validate choice is a number in range
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#entries[@]}" ]; then
            echo "Invalid selection."
            continue
        fi
        selection="${entries[$((choice-1))]}"
        if [ "$selection" == ".." ]; then
            # Go up to parent directory
            cd .. || echo "Unable to go to parent directory."
            continue
        fi
        if [ -d "$selection" ]; then
            # Enter the selected directory
            cd "$selection" || echo "Cannot enter directory: $selection"
            continue
        fi
        if [ -f "$selection" ]; then
            # File selected - show file operations menu
            while true; do
                echo ""
                echo "File: $selection"
                echo "1) Run/Open file"
                echo "2) Publish to GitHub Gist"
                echo "3) Delete file"
                echo "0) Cancel (back to list)"
                read -rp "Choose an action for '$selection': " file
                case "$file" in
                    1)  # Run or open the file
                        echo "Running '$selection'..."
                        if [ -x "$selection" ]; then
                            # Executable file
                            "./$selection"
                        elif [[ "$selection" == *.sh ]]; then
                            bash "$selection"
                        elif [[ "$selection" == *.py ]]; then
                            python3 "$selection"
                        else
                            # Try to open with xdg-open if available (for images, etc.)
                            if [ -n "$DISPLAY" ] && command -v xdg-open >/dev/null 2>&1; then
                                xdg-open "$selection" >/dev/null 2>&1 &
                            else
                                echo "No default handler to run this file."
                            fi
                        fi
                        echo "--- End of file output ---"
                        read -rp "Press Enter to continue..." dummy
                        ;;
                    2)  # Publish to GitHub Gist
                        if ! command -v curl >/dev/null 2>&1; then
                            echo "Error: curl is required to publish to GitHub."
                        else
                            echo "Publishing '$selection' to GitHub Gist..."
                            # Read file content and escape it for JSON
                            CONTENT=$(sed -e 's/\r//g' -e 's/\t/\\t/g' -e 's/\"/\\"/g' "$selection" | awk '{printf "%s\\n", $0}')
                            read -rp "Make gist public? [Y/n]: " pubchoice
                            if [[ "$pubchoice" =~ ^[Nn] ]]; then
                                pub_flag="false"
                            else
                                pub_flag="true"
                            fi
                            # Create JSON payload
                            read -r -d '' JSON_DATA <<EOF
{
  "description": "Uploaded via CoolPi",
  "public": ${pub_flag},
  "files": {
    "$(basename "$selection")": {
      "content": "$CONTENT"
    }
  }
}
EOF
# Send POST request to GitHub Gist API
response=$(curl -s -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "https://api.github.com/gists")
gist_url=$(echo "$response" | grep -oE '"html_url": *"[^"]*"' | head -1 | sed -E 's/.*"html_url": *"([^"]*)".*/\1/')
if [[ -n "$gist_url" ]]; then
    echo "File published! Gist URL: $gist_url"
else
    echo "Failed to create gist. Response: $response"
fi
read -rp "Press Enter to continue..." dummy
;;
3)  # Delete file
    read -rp "Are you sure you want to delete '$selection'? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -f -- "$selection"
        if [ ! -e "$selection" ]; then
            echo "File deleted."
            # After deletion, break out to refresh listing
            break
        else
            echo "Error: File could not be deleted."
        fi
    fi
    ;;

                        fi
                        ;;
                    0)
                        # Cancel file action
                        ;;
                    *)
                        echo "Invalid option."
                        ;;
                esac
                # If we broke out (file deletion or cancel), exit file action loop
                if [[ "$file" == "0" || "$file" == "3" && ! -e "$selection" ]]; then
                    break
                fi
            done
        fi
        # Continue back to file list loop (refresh current directory listing)
    done
    cd "$start_dir" || true   # return to original directory
}

# --- App Store Functions ---
install_package() {
    local pkg="$1"
    sudo apt-get update -qq
    sudo apt-get install -y "$pkg"
    if [ $? -eq 0 ]; then
        echo "Installation of '$pkg' successful."
    else
        echo "Error: failed to install '$pkg'."
    fi
    read -rp "Press Enter to continue..." dummy
}

app_store() {
    local choice category_choice app_choice
    while true; do
        echo ""
        echo "==== CoolPi App Store ===="
        echo "1) Games"
        echo "2) System Utilities"
        echo "3) Productivity"
        echo "4) Development"
        echo "0) Back to Main Menu"
        read -rp "Choose a category: " category_choice
        case "$category_choice" in
            1)  # Games
                while true; do
                    echo ""
                    echo "*** Games ***"
                    # Define games and their package names
                    local games=("ninvaders" "supertux")
                    local game_names=("nInvaders" "SuperTux")
                    for i in "${!games[@]}"; do
                        local pkg="${games[$i]}"
                        # Check if installed
                        if dpkg -s "$pkg" >/dev/null 2>&1; then
                            echo "$(($i+1))) ${game_names[$i]} (Installed)"
                        else
                            echo "$(($i+1))) ${game_names[$i]}"
                        fi
                    done
                    echo "0) Back"
                    read -rp "Choose a game to install: " app_choice
                    if [[ "$app_choice" == "0" ]]; then break; fi
                    if [[ "$app_choice" =~ ^[0-9]+$ ]] && [ "$app_choice" -ge 1 ] && [ "$app_choice" -le "${#games[@]}" ]; then
                        local index=$((app_choice-1))
                        local pkg="${games[$index]}"
                        if dpkg -s "$pkg" >/dev/null 2>&1; then
                            echo "'${game_names[$index]}' is already installed."
                        else
                            install_package "$pkg"
                        fi
                    else
                        echo "Invalid selection."
                    fi
                done
                ;;
            2)  # System Utilities
                while true; do
                    echo ""
                    echo "*** System Utilities ***"
                    local utils=("htop" "ncdu")
                    local util_names=("htop" "ncdu")
                    for i in "${!utils[@]}"; do
                        local pkg="${utils[$i]}"
                        if dpkg -s "$pkg" >/dev/null 2>&1; then
                            echo "$(($i+1))) ${util_names[$i]} (Installed)"
                        else
                            echo "$(($i+1))) ${util_names[$i]}"
                        fi
                    done
                    echo "0) Back"
                    read -rp "Choose a utility to install: " app_choice
                    if [[ "$app_choice" == "0" ]]; then break; fi
                    if [[ "$app_choice" =~ ^[0-9]+$ ]] && [ "$app_choice" -ge 1 ] && [ "$app_choice" -le "${#utils[@]}" ]; then
                        local index=$((app_choice-1))
                        local pkg="${utils[$index]}"
                        if dpkg -s "$pkg" >/dev/null 2>&1; then
                            echo "'${util_names[$index]}' is already installed."
                        else
                            install_package "$pkg"
                        fi
                    else
                        echo "Invalid selection."
                    fi
                done
                ;;
            3)  # Productivity
                while true; do
                    echo ""
                    echo "*** Productivity ***"
                    local prods=("libreoffice" "gimp")
                    local prod_names=("LibreOffice" "GIMP")
                    for i in "${!prods[@]}"; do
                        local pkg="${prods[$i]}"
                        if dpkg -s "$pkg" >/dev/null 2>&1; then
                            echo "$(($i+1))) ${prod_names[$i]} (Installed)"
                        else
                            echo "$(($i+1))) ${prod_names[$i]}"
                        fi
                    done
                    echo "0) Back"
                    read -rp "Choose a package to install: " app_choice
                    if [[ "$app_choice" == "0" ]]; then break; fi
                    if [[ "$app_choice" =~ ^[0-9]+$ ]] && [ "$app_choice" -ge 1 ] && [ "$app_choice" -le "${#prods[@]}" ]; then
                        local index=$((app_choice-1))
                        local pkg="${prods[$index]}"
                        if dpkg -s "$pkg" >/dev/null 2>&1; then
                            echo "'${prod_names[$index]}' is already installed."
                        else
                            install_package "$pkg"
                        fi
                    else
                        echo "Invalid selection."
                    fi
                done
                ;;
            4)  # Development
                while true; do
                    echo ""
                    echo "*** Development ***"
                    local devs=("git" "thonny" "geany")
                    local dev_names=("Git" "Thonny" "Geany")
                    for i in "${!devs[@]}"; do
                        local pkg="${devs[$i]}"
                        if dpkg -s "$pkg" >/dev/null 2>&1; then
                            echo "$(($i+1))) ${dev_names[$i]} (Installed)"
                        else
                            echo "$(($i+1))) ${dev_names[$i]}"
                        fi
                    done
                    echo "0) Back"
                    read -rp "Choose a package to install: " app_choice
                    if [[ "$app_choice" == "0" ]]; then break; fi
                    if [[ "$app_choice" =~ ^[0-9]+$ ]] && [ "$app_choice" -ge 1 ] && [ "$app_choice" -le "${#devs[@]}" ]; then
                        local index=$((app_choice-1))
                        local pkg="${devs[$index]}"
                        if dpkg -s "$pkg" >/dev/null 2>&1; then
                            echo "'${dev_names[$index]}' is already installed."
                        else
                            install_package "$pkg"
                        fi
                    else
                        echo "Invalid selection."
                    fi
                done
                ;;
            0)
                break
                ;;
            *)
                echo "Invalid selection."
                ;;
        esac
    done
}

# --- App Launcher Function ---
app_launcher() {
    echo ""
    echo "==== App Launcher (GUI Applications) ===="
    # Warn if not in GUI environment
    if [ -z "$DISPLAY" ]; then
        echo "Warning: No DISPLAY detected. You might not be in a GUI session."
    fi
    # Build list of GUI apps from .desktop files
    local apps=() app_names=() app_execs=()
    while IFS= read -r desktop_file; do
        # Skip if not a regular file
        [ -f "$desktop_file" ] || continue
        # Extract application name and exec command from .desktop file
        local name exec
        name=$(grep -m1 '^Name=' "$desktop_file" | sed 's/^Name=//')
        exec=$(grep -m1 '^Exec=' "$desktop_file" | sed 's/^Exec=//' | cut -d' ' -f1)
        if [ -n "$name" ] && [ -n "$exec" ]; then
            apps+=("$name")
            app_execs+=("$exec")
        fi
    done < <(find /usr/share/applications -maxdepth 1 -name "*.desktop" | sort)
    if [ "${#apps[@]}" -eq 0 ]; then
        echo "No GUI applications found."
        read -rp "Press Enter to go back..." dummy
        return
    fi
    local choice
    while true; do
        # Display applications list
        local i
        for i in "${!apps[@]}"; do
            printf "%2d) %s\n" $((i+1)) "${apps[$i]}"
        done
        echo " 0) Back to Main Menu"
        read -rp "Launch which app? " choice
        if [[ "$choice" == "0" ]]; then
            break
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#apps[@]}" ]; then
            local index=$((choice-1))
            local app_name="${apps[$index]}"
            local app_exec="${app_execs[$index]}"
            echo "Launching $app_name..."
            # Launch the application (background & disown to detach from terminal)
            nohup "$app_exec" >/dev/null 2>&1 &
            disown
            echo "$app_name launched (if GUI, check your desktop)."
            read -rp "Press Enter to continue..." dummy
        else
            echo "Invalid selection."
        fi
    done
}

# --- Main Program Loop ---
# If script is called via symlink "update-coolpi", perform update only
if [[ "$(basename "$0")" == "update-coolpi" ]]; then
    update_script
    exit 0
fi

# Ensure the update symlink is in place (attempt silently)
ensure_symlink

# If run without arguments, automatically check for updates on start
update_script  # you can comment this out to disable auto-update on each run

# Main menu loop
while true; do
    # Display main menu and storage meter
    echo ""
    echo "===== CoolPi Main Menu ====="
    echo "1) System Utilities"
    echo "2) File Manager"
    echo "3) App Store"
    echo "4) App Launcher"
    echo "5) Update CoolPi Script"
    echo "0) Exit"
    # Show storage usage bar for root filesystem
    used_pct=$(df -P / | awk 'NR==2 {print $5}' | sed 's/%//')
    blocks=$((used_pct/5)); ((blocks > 20)) && blocks=20
    bar=""
    for ((i=0; i<20; i++)); do
        [ $i -lt $blocks ] && bar+="#" || bar+="-"
    done
    total_size=$(df -h / | awk 'NR==2 {print $2}')
    printf "Disk Usage: [%s] %d%% of %s used\n" "$bar" "$used_pct" "$total_size"
    # Read main menu choice
    read -rp "Select an option: " REPLY
    case "$REPLY" in
        1) system_menu ;;
        2) file_manager ;;
        3) app_store ;;
        4) app_launcher ;;
        5) 
            update_script 
            # If update_script returns, it means no update was done or it failed.
            # In case of update, exec will have restarted the script.
            ;;
        0) 
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid selection. Please try again."
            ;;
    esac
done
