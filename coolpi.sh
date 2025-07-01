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
SCRIPT_URL="https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/coolpi.sh"  # URL to fetch latest script version for self-update
SCRIPT_PATH="$(realpath "$0")"
VERSION="1.0.0"  # Script version

# --- Self-Update Function ---
update_script() {
    echo "Checking for script updates..."
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
    echo "Update found! Applying update..."
    cp -f /tmp/coolpi_update.sh "$SCRIPT_PATH" && chmod +x "$SCRIPT_PATH"
    rm -f /tmp/coolpi_update.sh
    echo "CoolPi script has been updated. Restarting..."
    exec "$SCRIPT_PATH" "$@"
}

# --- Symlink Setup Function ---
ensure_symlink() {
    local link="/usr/local/bin/update-coolpi"
    if [ "$(readlink -f "$link")" != "$SCRIPT_PATH" ]; then
        sudo ln -sf "$SCRIPT_PATH" "$link" >/dev/null 2>&1 || return 0
    fi
}

# --- System Utilities Functions ---
show_storage_info() {
    echo "Storage Usage:"
    df -h /
    local used_pct=$(df -P / | awk 'NR==2 {print $5}' | sed 's/%//')
    local size=$(df -h / | awk 'NR==2 {print $2}')
    local blocks=$((used_pct/5))
    ((blocks > 20)) && blocks=20
    local bar=""
    for ((i=0; i<20; i++)); do
        if [ $i -lt $blocks ]; then bar+="#"; else bar+="-"; fi
    done
    echo "Root disk: [${bar}] ${used_pct}% of ${size} used"
}

open_shell() {
    echo "Opening an interactive shell. Type 'exit' to return to CoolPi."
    bash
}

system_menu() {
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
            1)
                read -rp "Are you sure you want to reboot? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy] ]]; then
                    echo "Rebooting now..."
                    sudo reboot
                    exit 0
                fi
                ;;
            2)
                read -rp "Are you sure you want to shutdown? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy] ]]; then
                    echo "Shutting down now..."
                    sudo poweroff
                    exit 0
                fi
                ;;
            3)
                show_storage_info
                read -rp "Press Enter to return to menu..." dummy
                ;;
            4)
                open_shell
                ;;
            5)
                sudo raspi-config
                echo "Exited raspi-config. Returning to menu..."
                ;;
            0)
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
    local start_dir="$PWD"
    local choice file selection
    while true; do
        echo ""
        echo "==== File Manager (current directory: $PWD) ===="
        local entries=()
        if [ "$PWD" != "/" ]; then
            entries+=("..")
        fi
        local item
        while IFS= read -r item; do
            entries+=("$item")
        done < <(ls -A)
        local idx=1
        for item in "${entries[@]}"; do
            [ -d "$item" ] && printf "%2d) %s/\n" "$idx" "$item" || printf "%2d) %s\n" "$idx" "$item"
            idx=$((idx+1))
        done
        echo " 0) Back to Main Menu"
        read -rp "Choose a file or directory: " choice
        if [[ "$choice" == "0" ]]; then
            break
        fi
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#entries[@]}" ]; then
            echo "Invalid selection."
            continue
        fi
        selection="${entries[$((choice-1))]}"
        if [ "$selection" == ".." ]; then
            cd .. || echo "Unable to go to parent directory."
            continue
        fi
        if [ -d "$selection" ]; then
            cd "$selection" || echo "Cannot enter directory: $selection"
            continue
        fi
        if [ -f "$selection" ]; then
            while true; do
                echo ""
                echo "File: $selection"
                echo "1) Run/Open file"
                echo "2) Publish to GitHub Gist"
                echo "3) Delete file"
                echo "0) Cancel (back to list)"
                read -rp "Choose an action for '$selection': " file
                case "$file" in
                    1)
                        echo "Running '$selection'..."
                        if [ -x "$selection" ]; then
                            "./$selection"
                        elif [[ "$selection" == *.sh ]]; then
                            bash "$selection"
                        elif [[ "$selection" == *.py ]]; then
                            python3 "$selection"
                        else
                            if [ -n "$DISPLAY" ] && command -v xdg-open >/dev/null 2>&1; then
                                xdg-open "$selection" >/dev/null 2>&1 &
                            else
                                echo "No default handler to run this file."
                            fi
                        fi
                        echo "--- End of file output ---"
                        read -rp "Press Enter to continue..." dummy
                        ;;
                    2)
                        if ! command -v curl >/dev/null 2>&1; then
                            echo "Error: curl is required to publish to GitHub."
                        else
                            echo "Publishing '$selection' to GitHub Gist..."
                            CONTENT=$(sed -e 's/\r//g' -e 's/\t/\\t/g' -e 's/\"/\\"/g' "$selection" | awk '{printf "%s\\n", $0}')
                            read -rp "Make gist public? [Y/n]: " pubchoice
                            if [[ "$pubchoice" =~ ^[Nn] ]]; then
                                pub_flag="false"
                            else
                                pub_flag="true"
                            fi
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
                            response=$(curl -s -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "https://api.github.com/gists")
                            gist_url=$(echo "$response" | grep -oE '"html_url": *"[^"]*"' | head -1 | sed -E 's/.*"html_url": *"([^"]*)".*/\1/')
                            if [[ -n "$gist_url" ]]; then
                                echo "File published! Gist URL: $gist_url"
                            else
                                echo "Failed to create gist. Response: $response"
                            fi
                            read -rp "Press Enter to continue..." dummy
                        fi
                        ;;
                    3)
                        read -rp "Are you sure you want to delete '$selection'? [y/N]: " confirm
                        if [[ "$confirm" =~ ^[Yy]$ ]]; then
                            rm -f -- "$selection"
                            if [ ! -e "$selection" ]; then
                                echo "File deleted."
                                break
                            else
                                echo "Error: File could not be deleted."
                            fi
                        fi
                        ;;
                    0)
                        ;;
                    *)
                        echo "Invalid option."
                        ;;
                esac
                if [[ "$file" == "0" || ( "$file" == "3" && ! -e "$selection" ) ]]; then
                    break
                fi
            done
        fi
    done
    cd "$start_dir" || true
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
            1)
                while true; do
                    echo ""
                    echo "*** Games ***"
                    local games=("ninvaders" "supertux")
                    local game_names=("nInvaders" "SuperTux")
                    for i in "${!games[@]}"; do
                        local pkg="${games[$i]}"
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
            2)
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
            3)
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
            4)
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
    if [ -z "$DISPLAY" ]; then
        echo "Warning: No DISPLAY detected. You might not be in a GUI session."
    fi
    local apps=() app_execs=()
    while IFS= read -r desktop_file; do
        [ -f "$desktop_file" ] || continue
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
if [[ "$(basename "$0")" == "update-coolpi" ]]; then
    update_script
    exit 0
fi

ensure_symlink

update_script  # you can comment this out to disable auto-update on each run

while true; do
    echo ""
    echo "===== CoolPi Main Menu ====="
    echo "1) System Utilities"
    echo "2) File Manager"
    echo "3) App Store"
    echo "4) App Launcher"
    echo "5) Update CoolPi Script"
    echo "0) Exit"
    used_pct=$(df -P / | awk 'NR==2 {print $5}' | sed 's/%//')
    blocks=$((used_pct/5)); ((blocks > 20)) && blocks=20
    bar=""
    for ((i=0; i<20; i++)); do
        [ $i -lt $blocks ] && bar+="#" || bar+="-"
    done
    total_size=$(df -h / | awk 'NR==2 {print $2}')
    printf "Disk Usage: [%s] %d%% of %s used\n" "$bar" "$used_pct" "$total_size"
    read -rp "Select an option: " REPLY
    case "$REPLY" in
        1) system_menu ;;
        2) file_manager ;;
        3) app_store ;;
        4) app_launcher ;;
        5)
            update_script
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
