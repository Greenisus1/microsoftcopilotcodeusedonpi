#!/bin/bash

green='\033[0;32m'
cyan='\033[0;36m'
bold='\033[1m'
reset='\033[0m'

echo -e "${cyan}${bold}"
echo "╔════════════════════════════════════╗"
echo "║   🧹 Uninstalling Copilot Desktop   ║"
echo "╚════════════════════════════════════╝"
echo -e "${reset}"

# Remove snap package
if snap list | grep -q copilot-desktop; then
    echo -e "${cyan}📦 Removing Copilot Desktop...${reset}"
    sudo snap remove copilot-desktop
else
    echo -e "${green}✔️ Copilot Desktop not installed.${reset}"
fi

# Remove desktop shortcut
DESKTOP_ICON="$HOME/Desktop/copilot.desktop"
if [ -f "$DESKTOP_ICON" ]; then
    echo -e "${cyan}🗑️ Removing desktop shortcut...${reset}"
    rm "$DESKTOP_ICON"
else
    echo -e "${green}✔️ Desktop shortcut not found.${reset}"
fi

# Remove taskbar entry if present
PANEL_CFG="$HOME/.config/wf-panel-pi.ini"
if [ -f "$PANEL_CFG" ]; then
    echo -e "${cyan}📉 Removing taskbar launcher entry...${reset}"
    sed -i '/copilot\.desktop/d' "$PANEL_CFG"
else
    echo -e "${green}✔️ Taskbar config not found. Nothing to clean.${reset}"
fi

# Optional: remove audio/bluetooth support (comment these out if you want to keep them)
echo -e "${cyan}❓ Do you want to remove audio & Bluetooth packages? (y/N)${reset}"
read -r wipeExtras
if [[ "$wipeExtras" =~ ^[Yy]$ ]]; then
    echo -e "${cyan}🔧 Purging related packages...${reset}"
    sudo apt purge -y pulseaudio pavucontrol alsa-utils bluetooth bluez pulseaudio-module-bluetooth
    sudo apt autoremove -y
    echo -e "${green}🧼 Extra system packages removed.${reset}"
else
    echo -e "${cyan}➡️ Keeping system audio and Bluetooth tools.${reset}"
fi

echo -e "\n${bold}${green}✅ Copilot fully uninstalled!${reset}"
