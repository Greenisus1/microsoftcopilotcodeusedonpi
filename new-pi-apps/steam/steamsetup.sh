#!/bin/bash
# 🚀 Smart launcher for full Pi backup + Steam installer (calls file2.sh)

set -e

# === Dog1 Banner + Hidden Easter Egg ===
cat << "DOG"
            █   ████████     ███    ██     █         █   █████████     
        █████   █      █    █       █      ███████████      ███          
        █   █   █      █    █  █    █      ███████████      ███                                                                                       
        █████   ████████    ████  █████    █         █  ███████████
DOG
echo -e "\e[30mHI\e[0m"  # Hidden "HI" in black

# === Repo Info ===
REPO_OWNER="Greenisus1" # === change if you fork it===
REPO_NAME="microsoftcopilotcodeusedonpi" # === change if you fork it===
SCRIPT_NAME="file2.sh" # === change if you fork it===
GITHUB_URL="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main/$SCRIPT_NAME" # === change if you fork it===
LOCAL_TEMP="/tmp/$SCRIPT_NAME" # === change if you fork it===

log() {
  echo -e "[$(date +'%H:%M:%S')] $1"
}

# === Check prerequisites ===
if ! command -v curl >/dev/null; then
  echo "❌ curl is required but not installed. Please install it first."
  exit 1
fi

if ! ping -q -c 1 github.com >/dev/null 2>&1; then
  echo "❌ No internet connection or GitHub unreachable."
  exit 1
fi

# === Fetch file2.sh ===
log "📥 Fetching latest $SCRIPT_NAME from GitHub..."
if curl -fsSL "$GITHUB_URL" -o "$LOCAL_TEMP"; then
  chmod +x "$LOCAL_TEMP"
else
  echo "❌ Failed to download $SCRIPT_NAME. Check your URL or connection."
  exit 1
fi

# === Run file2.sh with inherited args ===
log "🚀 Running full backup + installer..."
bash "$LOCAL_TEMP" "$@"
