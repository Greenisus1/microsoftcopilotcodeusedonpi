#!/bin/bash

# Define variables
DESKTOP_FILE="$HOME/Desktop/copilot.desktop"
PANEL_CONFIG="$HOME/.config/wf-panel-pi.ini"
LAUNCHER_ID="launcher_000006"

# Create the .desktop shortcut
echo "Creating Copilot desktop shortcut..."
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Copilot
Comment=Launch Microsoft Copilot
Exec=chromium-browser --app=https://www.bing.com/search?q=Bing+AI&showconv=1&FORM=hpcodx
Icon=chromium
Terminal=false
Type=Application
Categories=Utility;
EOF

chmod +x "$DESKTOP_FILE"

# Add to taskbar if not already present
echo "Adding Copilot to taskbar..."
if grep -q "$LAUNCHER_ID" "$PANEL_CONFIG"; then
    echo "Copilot already in taskbar."
else
    echo "$LAUNCHER_ID=copilot.desktop" >> "$PANEL_CONFIG"
    echo "Added Copilot to taskbar config."
fi

# Done
echo "✅ Copilot shortcut and taskbar entry created. Reboot to apply changes."
