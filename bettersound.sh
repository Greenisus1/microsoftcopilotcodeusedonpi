#!/bin/bash

echo "🔧 Installing Better Sound Futures on Raspberry Pi..."

# STEP 1: System update
echo "📦 Updating system..."
sudo apt update && sudo apt upgrade -y

# STEP 2: Install essential sound packages
echo "🔊 Installing audio packages..."
sudo apt install -y pulseaudio pulseaudio-utils alsa-utils sox libasound2-dev \
  pavucontrol volumeicon-alsa

# STEP 3: Optional enhancements
echo "🎚️ Installing optional sound enhancements..."
sudo apt install -y libavcodec-extra lame flac mpg123

# STEP 4: Enable PulseAudio system-wide
echo "🔁 Configuring PulseAudio for system-wide use..."
sudo sed -i 's/; system-instance = yes/system-instance = yes/' /etc/pulse/daemon.conf
sudo systemctl --system enable pulseaudio.service

# STEP 5: Autostart volume control tray icon
echo "🖥️ Adding volumeicon to autostart..."
mkdir -p ~/.config/autostart
cat <<EOF > ~/.config/autostart/volumeicon.desktop
[Desktop Entry]
Type=Application
Exec=volumeicon
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Volume Icon
EOF

# STEP 6: Confirm sound config
echo "✅ Finalizing configuration..."
pulseaudio --check && echo "PulseAudio is running." || echo "⚠️ PulseAudio not running."

echo "🎉 Better Sound Futures installation complete!"
