#!/bin/bash
# coolpi_nav.sh – CoolPi File Explorer + Run or GitHub Publish

START_DIR="$HOME"
TMP="/tmp/coolpi_nav.txt"
GITHUB_API="https://api.github.com"

# Ensure prerequisites
for cmd in dialog curl base64 jq; do
  if ! command -v $cmd &>/dev/null; then
    echo "[INFO] Installing missing '$cmd'..."
    sudo apt update && sudo apt install -y $cmd
  fi
done

# Main browser
browse() {
  DIR="$1"
  while true; do
    mapfile -t items < <(
      printf "%s\0%s\n" \
        "${DIR}"/* |
      while IFS= read -r -d '' f; do
        base=$(basename "$f")
        if [ -d "$f" ]; then
          printf "%s\t📁 %s\n" "$f" "$base"
        else
          printf "%s\t%s\n" "$f" "$base"
        fi
      done
    )
    dialog --backtitle "CoolPi Navigator" \
           --title "Browse: $DIR" \
           --menu "Choose a file or folder" 20 70 12 \
           "${items[@]}" 2>"$TMP"
    sel=$(<"$TMP")
    [ -z "$sel" ] && break
    if [ -d "$sel" ]; then
      DIR="$sel"
    else
      file_menu "$sel"
    fi
  done
}

# File action menu
file_menu() {
  FILE="$1"
  dialog --backtitle "CoolPi Navigator" \
         --title "File: $(basename "$FILE")" \
         --menu "1 Run  2 Publish  3 Back" 10 50 3 \
         1 "Run file" \
         2 "Publish to GitHub" \
         3 "Back" 2>"$TMP"
  case $(<"$TMP") in
    1) run_file "$FILE" ;;
    2) github_publish "$FILE" ;;
    *) return ;;
  esac
}

# Run file with auto-detect
run_file() {
  FILE="$1"
  ext="${FILE##*.}"
  case "$ext" in
    py)
      cmd=python3; pkg=python3 ;;
    js)
      cmd=node;     pkg=nodejs   ;;
    sh)
      cmd=bash;     pkg=bash     ;;
    rb)
      cmd=ruby;     pkg=ruby     ;;
    pl)
      cmd=perl;     pkg=perl     ;;
    *)
      dialog --msgbox "Unsupported ext: .$ext" 6 40; return ;;
  esac
  # Install if missing
  if ! command -v $cmd &>/dev/null; then
    dialog --infobox "Installing $pkg..." 4 40
    sudo apt update && sudo apt install -y $pkg
  fi
  # Execute and capture
  OUTPUT=$("$cmd" "$FILE" 2>&1)
  dialog --backtitle "CoolPi Navigator" \
         --title "Output of $(basename "$FILE")" \
         --msgbox "$OUTPUT" 20 70
}

# Publish to GitHub
github_publish() {
  FILE="$1"
  # 1) get token
  dialog --backtitle "GitHub Publish" \
         --inputbox "Enter your GitHub PAT:" 8 50 2>"$TMP"
  TOKEN=$(<"$TMP")
  # 2) list repos
  REPOS_JSON=$(curl -s -H "Authorization: token $TOKEN" \
    "$GITHUB_API/user/repos?per_page=100")
  mapfile -t repos < <(jq -r '.[].full_name' <<<"$REPOS_JSON")
  choices=()
  for r in "${repos[@]}"; do
    choices+=("$r" "")
  done
  dialog --backtitle "GitHub Publish" \
         --menu "Select target repo:" 20 60 12 \
         "${choices[@]}" 2>"$TMP"
  REPO=$(<"$TMP")
  [ -z "$REPO" ] && return

  # 3) choose existing or upload new
  dialog --backtitle "GitHub Publish" \
         --menu "1 Upload new file\n2 Cancel" 8 40 2 \
         1 "Upload new file" \
         2 "Cancel" 2>"$TMP"
  [ "$( <"$TMP" )" -ne 1 ] && return

  # 4) read & encode, then PUT
  FNAME=$(basename "$FILE")
  CONTENT=$(base64 < "$FILE")
  PAYLOAD=$(jq -n --arg msg "Add $FNAME" \
                   --arg content "$CONTENT" \
                   '{message:$msg, content:$content}')
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT \
    -H "Authorization: token $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$GITHUB_API/repos/$REPO/contents/$FNAME")

  if [ "$HTTP" -eq 201 ] || [ "$HTTP" -eq 200 ]; then
    dialog --msgbox "✔️ Uploaded $FNAME to $REPO" 6 50
  else
    dialog --msgbox "❌ Failed (HTTP $HTTP)" 6 40
  fi
}

### Kick off
browse "$START_DIR"
clear
