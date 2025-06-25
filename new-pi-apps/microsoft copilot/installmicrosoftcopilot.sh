#!/bin/bash

green='\033[0;32m'
cyan='\033[0;36m'
bold='\033[1m'
reset='\033[0m'

# 🪄 Show welcome banner popup
zenity --info --title="Copilot Installer Wizard" \
  --text="Welcome to the ✨ Microsoft Copilot Installer ✨\n\nThis will install Copilot Desktop, audio support, microphone access, and Bluetooth tools. on your pi"

function pause() {
  read -rp $'\n➡️  Press Enter to continue...'
}

function check_package() {
  dpkg -s "$1" &>/dev/null
}

function install_if_missing() {
  local pkg="$1"
  local name="$2"
  if check_package "$pkg"; then
    echo -e "${green}✔️ $name is already installed.${reset}"
  else
    echo -e "${cyan}🔧 Installing $name...${reset}"
    sudo apt update && sudo apt install -y "$pkg"
  fi
}

function install_audio_stack() {
  echo -e "\n🔊 Checking audio & microphone packages..."
  install_if_missing "alsa-utils" "ALSA utilities"
  install_if_missing "pulseaudio" "PulseAudio"
  install_if_missing "pavucontrol" "PulseAudio Volume Control"
}

function install_bluetooth_stack() {
  echo -e "\n📶 Checking Bluetooth stack..."
  install_if_missing "bluetooth" "Bluetooth core"
  install_if_missing "bluez" "BlueZ Bluetooth tools"
  install_if_missing "pulseaudio-module-bluetooth" "PulseAudio Bluetooth module"
  sudo systemctl enable bluetooth
  sudo systemctl start bluetooth
}

function install_snapd() {
  if ! command -v snap &>/dev/null; then
    echo -e "${cyan}📦 Installing snapd...${reset}"
    sudo apt update && sudo apt install -y snapd
    echo -e "${green}✅ snapd installed. Reboot required.${reset}"
    pause
    sudo reboot
  else
    echo -e "${green}✔️ snapd is already installed.${reset}"
  fi
}

function install_copilot_desktop() {
  if ! snap list | grep -q copilot-desktop; then
    echo -e "${cyan}🧠 Installing Copilot Desktop...${reset}"
    sudo snap install copilot-desktop
  else
    echo -e "${green}✔️ Copilot Desktop is already installed.${reset}"
  fi
}

function enable_mic_access() {
  echo -e "${cyan}🎤 Enabling microphone access...${reset}"
  sudo snap connect copilot-desktop:audio-record
}

function create_desktop_shortcut() {
  local target="$HOME/Desktop/copilot.desktop"
  mkdir -p "$HOME/Desktop"

  cat > "$target" <<EOF
[Desktop Entry]
Name=Copilot
Comment=Launch Microsoft Copilot
Exec=snap run copilot-desktop
Icon=chromium
Terminal=false
Type=Application
Categories=Utility;
EOF

  chmod +x "$target"
  echo -e "${green}🚀 Shortcut created on Desktop.${reset}"
}

function add_to_taskbar() {
  local config="$HOME/.config/wf-panel-pi.ini"
  local entry="launcher_000006=copilot.desktop"

  if [ -f "$config" ]; then
    if grep -q "$entry" "$config"; then
      echo -e "${green}📌 Copilot already in taskbar config.${reset}"
    else
      echo "$entry" >> "$config"
      echo -e "${green}📌 Copilot added to taskbar. Reboot to apply.${reset}"
    fi
  else
    echo -e "${cyan}⚠️ Taskbar config not found. Skipping.${reset}"
  fi
}

function run_installer() {
  install_audio_stack
  install_bluetooth_stack
  install_snapd
  install_copilot_desktop
  enable_mic_access
  create_desktop_shortcut
  add_to_taskbar
  echo -e "\n${green}🎉 Done! You can now launch Copilot from your Desktop.${reset}"
}

run_installer
