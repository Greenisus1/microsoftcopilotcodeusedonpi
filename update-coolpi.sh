#!/bin/bash
set -e

# URL of the latest CoolPi script
REPO_URL="https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/coolpi.sh"

# Temporary file for download
TMPFILE="$(mktemp /tmp/coolpi.XXXXXX)"

echo "→ Downloading latest CoolPi..."
curl -fsSL "$REPO_URL" -o "$TMPFILE" || {
  echo "✖ Failed to download from $REPO_URL"
  exit 1
}

# Determine where coolpi.sh is installed
if [ -f "/usr/local/bin/coolpi" ]; then
  DEST="/usr/local/bin/coolpi"
elif [ -f "$HOME/coolpi.sh" ]; then
  DEST="$HOME/coolpi.sh"
else
  echo "✖ No existing CoolPi installation found."
  echo "  Please install coolpi.sh first (see README)."
  rm -f "$TMPFILE"
  exit 1
fi

echo "→ Installing to $DEST"
mv "$TMPFILE" "$DEST"
chmod +x "$DEST"

echo "✔ CoolPi updated successfully at $DEST"
