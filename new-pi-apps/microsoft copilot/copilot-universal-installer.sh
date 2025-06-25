#!/bin/bash

# ───── UI Styling ─────
green='\033[0;32m'
cyan='\033[0;36m'
bold='\033[1m'
reset='\033[0m'

# ───── Welcome Banner ─────
if command -v zenity &>/dev/null; then
    zenity --info --title="Copilot Installer Wizard" \
      --text="🚀 Welcome to the Microsoft Copilot Installer\n\nWe'll install audio, mic, Bluetooth, and Copilot Desktop!"
else
    echo -e "${cyan}Hint: Install zenity for GUI banners: sudo apt install zenity${reset}"
fi

# ───── Helpers ─────
pause() { read -rp $'\n➡️  Press Enter to continue...'; }
check_installed() { dpkg -s "$1" &>/dev/null; }
install_pkg() {
    if ! check_installed "$1"; then
        echo -e "${cyan}🔧 Installing $2...${reset}"
        sudo apt update && sudo apt install -y "$1"
    else
        echo -e "${green}✔️ $2 already installed.${reset}"
    fi
}

# ───── Install Stacks ─────
echo -e "\n🔊 Checking audio/mic packages..."
install_pkg "alsa-utils" "ALSA utilities"
install_pkg "pulseaudio" "PulseAudio"
install_pkg "pavucontrol" "PulseAudio volume control"

echo -e "\n📶 Checking Bluetooth packages..."
install_pkg "bluetooth" "Bluetooth core"
install_pkg "bluez" "BlueZ Bluetooth tools"
install_pkg "pulseaudio-module-bluetooth" "PulseAudio Bluetooth module"
sudo systemctl enable bluetooth && sudo systemctl start bluetooth

echo -e "\n📦 Checking snapd..."
install_pkg "snapd" "snapd (Snap Package Manager)"

# ───── Install Copilot Desktop ─────
if ! snap list | grep -q copilot-desktop; then
    echo -e "${cyan}🧠 Installing Copilot Desktop...${reset}"
    sudo snap install copilot-desktop
else
    echo -e "${green}✔️ Copilot Desktop is already installed.${reset}"
fi

# ───── Enable Mic Access ─────
echo -e "${cyan}🎤 Enabling microphone access...${reset}"
sudo snap connect copilot-desktop:audio-record

# ───── Create .desktop Shortcut ─────
echo -e "${cyan}🖼️ Creating Copilot Desktop icon...${reset}"
mkdir -p "$HOME/Desktop"
cat > "$HOME/Desktop/copilot.desktop" <<EOF
[Desktop Entry]
Name=Copilot
Comment=Launch Microsoft Copilot
Exec=snap run copilot-desktop
Icon=chromium
Terminal=false
Type=Application
Categories=Utility;
EOF
chmod +x "$HOME/Desktop/copilot.desktop"
echo -e "${green}🚀 Desktop shortcut added.${reset}"

# ───── Taskbar Integration ─────
PANEL_CFG="$HOME/.config/wf-panel-pi.ini"
if [ -f "$PANEL_CFG" ]; then
    ENTRY="launcher_000006=copilot.desktop"
    if grep -q "$ENTRY" "$PANEL_CFG"; then
        echo -e "${green}📌 Already pinned to taskbar.${reset}"
    else
        echo "$ENTRY" >> "$PANEL_CFG"
        echo -e "${green}📌 Added to taskbar config. Reboot to apply.${reset}"
    fi
else
    echo -e "${cyan}⚠️ Taskbar config not found. Skipping pin.${reset}"
fi

# ───── Done ─────
echo -e "\n${bold}${green}🎉 All done! Launch Copilot from your desktop or reboot to see it on your taskbar.${reset}"
