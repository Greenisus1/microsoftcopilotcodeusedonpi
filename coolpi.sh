#!/bin/bash
# CoolPi v2.0 - File Manager, App Launcher, and Utilities

TMP="/tmp/coolpi_menu.txt"
START_DIR="$HOME"
GITHUB_API="https://api.github.com"

# Ensure dependencies
for cmd in dialog curl base64 jq; do
  if ! command -v $cmd &>/dev/null; then
    echo "[INFO] Installing missing $cmd..."
    sudo apt update && sudo apt install -y $cmd
  fi
done

# Banner
show_banner() {
  clear
  echo "╔════════════════════════════════════╗"
  echo "║          🚀 COOLPI v2.0            ║"
  echo "╠════════════════════════════════════╣"
  echo "║      Terminal Control Hub          ║"
  echo "║    File Runner + GitHub Push       ║"
  echo "║      System Tools + App Launch     ║"
  echo "╚════════════════════════════════════╝"
  sleep 1
}

# --- HOME SCREEN ---
main_menu() {
  while true; do
    dialog --clear --backtitle "CoolPi v2.0" \
      --title "Home" \
      --menu "Choose an option" 15 60 7 \
      1 "📁 Browse Files" \
      2 "🚀 Launch Installed Apps" \
      3 "⚙️  System Utilities" \
      4 "🛍️  CoolPi App Store (COMING SOON)" \
      5 "❌ Exit" 2>"$TMP"
    case $(<"$TMP") in
      1) browse "$START_DIR" ;;
      2) launch_apps ;;
      3) system_utils ;;
      4) dialog --colors --msgbox "\Z1🛠️ CoolPi App Store coming soon!" 6 50 ;;
      5) clear; exit 0 ;;
    esac
  done
}

# --- FILE BROWSER ---
browse() {
  DIR="$1"
  while true; do
    mapfile -t entries < <(find "$DIR" -maxdepth 1 -mindepth 1 | sort)
    MENU=()
    for f in "${entries[@]}"; do
      base=$(basename "$f")
      [[ -d "$f" ]] && base="📁 $base"
      MENU+=("$f" "$base")
    done
    MENU+=("..BACK.." "⬅️ Return to Home")
    dialog --title "Browsing: $DIR" \
      --menu "Select item" 20 70 12 \
      "${MENU[@]}" 2>"$TMP" || break
    sel=$(<"$TMP")
    [ "$sel" = "..BACK.." ] && break
    if [ -d "$sel" ]; then
      browse "$sel"
    else
      file_action "$sel"
    fi
  done
}

# --- FILE ACTION MENU ---
file_action() {
  FILE="$1"
  dialog --title "File: $(basename "$FILE")" \
    --menu "Select action" 10 50 3 \
    1 "▶️ Run File" \
    2 "📤 Publish to GitHub" \
    3 "⬅️ Back to Home" 2>"$TMP"
  case $(<"$TMP") in
    1) run_file "$FILE" ;;
    2) github_publish "$FILE" ;;
    *) return ;;
  esac
}

# --- RUN FILE ---
run_file() {
  FILE="$1"
  EXT="${FILE##*.}"
  case "$EXT" in
    py) cmd=python3; pkg=python3 ;;
    sh) cmd=bash; pkg=bash ;;
    js) cmd=node; pkg=nodejs ;;
    rb) cmd=ruby; pkg=ruby ;;
    pl) cmd=perl; pkg=perl ;;
    *) dialog --msgbox "❌ Unsupported type: .$EXT" 6 40; return ;;
  esac

  if ! command -v $cmd &>/dev/null; then
    dialog --infobox "Installing $pkg..." 5 40
    sudo apt update && sudo apt install -y $pkg
  fi

  OUTPUT=$($cmd "$FILE" 2>&1)
  dialog --title "Output" --msgbox "$OUTPUT" 20 70
}

# --- GITHUB PUBLISH ---
github_publish() {
  FILE="$1"
  dialog --inputbox "Enter your GitHub Token (PAT):" 8 50 2>"$TMP"
  TOKEN=$(<"$TMP")
  dialog --inputbox "Enter repo name (e.g. user/repo):" 8 50 2>"$TMP"
  REPO=$(<"$TMP")
  FNAME=$(basename "$FILE")
  CONTENT=$(base64 < "$FILE")

  PAYLOAD=$(jq -n --arg m "Upload $FNAME" --arg c "$CONTENT" \
    '{message:$m, content:$c}')
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT -H "Authorization: token $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$GITHUB_API/repos/$REPO/contents/$FNAME")

  if [ "$HTTP" -eq 201 ] || [ "$HTTP" -eq 200 ]; then
    dialog --msgbox "✅ $FNAME uploaded to $REPO" 6 50
  else
    dialog --msgbox "❌ Upload failed (HTTP $HTTP)" 6 40
  fi
}

# --- APP LAUNCHER ---
launch_apps() {
  mapfile -t apps < <(find /usr/share/applications ~/.local/share/applications -name "*.desktop" 2>/dev/null)
  MENU=()
  for f in "${apps[@]}"; do
    NAME=$(grep -m1 "^Name=" "$f" | cut -d= -f2)
    EXE=$(grep -m1 "^Exec=" "$f" | cut -d= -f2 | cut -d' ' -f1)
    MENU+=("$EXE" "$NAME")
  done
  dialog --title "Installed Apps" \
    --menu "Choose to launch:" 20 60 12 \
    "${MENU[@]}" 2>"$TMP" || return
  sel=$(<"$TMP")
  "$sel" &
}

# --- SYSTEM UTILITIES ---
system_utils() {
  dialog --title "System Tools" \
    --menu "Pick a system action:" 12 50 4 \
    1 "🔁 Reboot" \
    2 "⏻ Shutdown" \
    3 "⬅️ Back" 2>"$TMP"
  case $(<"$TMP") in
    1) sudo reboot ;;
    2) sudo shutdown now ;;
    *) return ;;
  esac
}

# --- Run It ---
show_banner
main_menu
