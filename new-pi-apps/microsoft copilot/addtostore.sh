#!/bin/bash

# Define variables
APP_NAME="Microsoft-Copilot"
REPO_URL="https://github.com/Greenisus1/microsoftcopilotcodeusedonpi"
APP_PATH="new-pi-apps/microsoft copilot"
PI_APPS_DIR="$HOME/pi-apps/apps"

# Clone or update your repo locally
TEMP_DIR=$(mktemp -d)
git clone --depth=1 "$REPO_URL" "$TEMP_DIR"

# Create the app directory inside Pi-Apps
mkdir -p "$PI_APPS_DIR/$APP_NAME"

# Copy your app contents into the Pi-Apps folder
cp -r "$TEMP_DIR/$APP_PATH/"* "$PI_APPS_DIR/$APP_NAME/"

# Clean up temporary clone
rm -rf "$TEMP_DIR"

# Done
echo "✅ $APP_NAME has been installed into Pi-Apps. Launching GUI..."

# Run Pi-Apps GUI
cd "$HOME/pi-apps"
./gui
