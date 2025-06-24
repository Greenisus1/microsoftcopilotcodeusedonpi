#!/bin/bash
# Smart launcher for Pi full-system backup & installer via file2.sh

set -e

REPO_OWNER="Greenisus1"
REPO_NAME="microsoftcopilotcodeusedonpi"
SCRIPT_NAME="file2.sh"
GITHUB_URL="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main/$SCRIPT_NAME"
LOCAL_TEMP="/tmp/$SCRIPT_NAME"

log() {
  echo -e "[$(date +'%H:%M:%S')] $1"
}

# Step 1: Check prerequisites
if ! command -v curl >/dev/null; then
  echo "❌ curl is required but not installed. Please install it first."
  exit 1
fi

if ! ping -q -c 1 github.com >/dev/null; then
  echo "❌ No internet connection or GitHub unreachable."
  exit 1
fi

# Step 2: Download file2.sh from GitHub
log "📥 Fetching latest $SCRIPT_NAME from GitHub..."
if curl -fsSL "$GITHUB_URL" -o "$LOCAL_TEMP"; then
  chmod +x "$LOCAL_TEMP"
else
  echo "❌ Failed to download $SCRIPT_NAME. Check your URL or connection."
  exit 1
fi

# Step 3: Run it
log "🚀 Running full installer..."
bash "$LOCAL_TEMP" "$@"
