#!/bin/bash
# === CoolPi v2.1 - Self-Updating Terminal UI ===

REPO_URL="https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/coolpi.sh"
LOCAL_FILE="$0"
TMP="/tmp/coolpi_menu.txt"
START_DIR="$HOME"
APP_DIR="$HOME/coolpi/done-downloads"
mkdir -p "$APP_DIR"

# === Auto-Updater ===
curl -s "$REPO_URL" -o /tmp/coolpi_latest.sh
if [ -s /tmp/coolpi_latest.sh ]; then
  LOCAL_HASH=$(sha256sum "$LOCAL_FILE" | awk '{print $1}')
  REMOTE_HASH=$(sha256sum /tmp/coolpi_latest.sh | awk '{print $1}')
  if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
    cp /tmp/coolpi_latest.sh "$LOCAL_FILE"
    chmod +x "$LOCAL_FILE"
    exec "$LOCAL_FILE"
  fi
fi

# === Dependencies ===
for cmd in dialog curl jq base64 sha256sum; do
  command -v "$cmd" &>/dev/null || sudo apt install -y "$cmd"
done

# === Banner ===
show_banner() {
  clear
  echo "=============================="
  echo "         COOLPI v2.1"
  echo "=============================="
  echo " File Manager · App Store · Tools"
  echo "=============================="
  sleep 1
}

# === Storage Meter ===
show_storage() {
  usage=$(df / | awk 'NR==2 {print $3}')
  total=$(df / | awk 'NR==2 {print $2}')
  free=$(df / | awk 'NR==2 {print $4}')
  percent=$(df -h / | awk 'NR==2 {print $5}')
  used_blocks=$(( usage * 30 / total ))
  free_blocks=$(( free * 30 / total ))
  sys_blocks=$(( 30 - used_blocks - free_blocks ))
  bar=""
  for ((i=0;i<used_blocks;i++)); do bar+="\Z1█"; done
  for ((i=0;i<sys_blocks;i++));  do bar+="\Z3█"; done
  for ((i=0;i<free_blocks;i++)); do bar+="\Z2█"; done
  dialog --colors --title "Storage" --msgbox \
  "\n/ Usage: $percent\n\n$bar\n\n\Z1Used\Z0 | \Z3System\Z0 | \Z2Free\Z0" 12 60
}

# === File Actions ===
delete_file() {
  file="$1"
  dialog --yesno "Delete:\n$file" 8 50 && rm -f "$file"
}

run_file() {
  file="$1"; ext="${file##*.}"
  case "$ext" in
    py) cmd=python3 ;;
    sh) cmd=bash ;;
    js) cmd=node ;;
    rb) cmd=ruby ;;
    pl) cmd=perl ;;
    *) dialog --msgbox "Unsupported: .$ext" 6 40; return ;;
  esac
  command -v "$cmd" &>/dev/null || sudo apt install -y "$cmd"
  output=$("$cmd" "$file" 2>&1)
  dialog --title "Output" --msgbox "$output" 20 70
}

github_publish() {
  file="$1"
  dialog --inputbox "GitHub Token:" 8 50 2>"$TMP"; token=$(<"$TMP")
  dialog --inputbox "Repo (user/repo):" 8 50 2>"$TMP"; repo=$(<"$TMP")
  fname=$(basename "$file")
  content=$(base64 < "$file")
  json=$(jq -n --arg msg "Add $fname" --arg c "$content" '{message:$msg, content:$c}')
  http=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT -H "Authorization: token $token" \
    -H "Content-Type: application/json" -d "$json" \
    "https://api.github.com/repos/$repo/contents/$fname")
  [[ "$http" =~ 20. ]] && dialog --msgbox "Uploaded to $repo" 6 40 || dialog --msgbox "HTTP $http error" 6 40
}

file_action() {
  file="$1"
  dialog --menu "File: $(basename "$file")" 12 50 4 \
    1 "Run File" 2 "Publish to GitHub" 3 "Delete File" 4 "Back" 2>"$TMP"
  case $(<"$TMP") in
    1) run_file "$file" ;;
    2) github_publish "$file" ;;
    3) delete_file "$file" ;;
    *) return ;;
  esac
}

browse() {
  dir="$1"
  while true; do
    mapfile -t items < <(find "$dir" -maxdepth 1 -mindepth 1 | sort)
    menu=()
    for e in "${items[@]}"; do
      name=$(basename "$e")
      [[ -d "$e" ]] && name="[DIR] $name"
      menu+=("$e" "$name")
    done
    menu+=("..BACK.." "Return")
    dialog --title "Browsing $dir" --menu "Choose file/folder:" 20 60 12 "${menu[@]}" 2>"$TMP" || break
    sel=$(<"$TMP")
    [[ "$sel" == "..BACK.." ]] && break
    [[ -d "$sel" ]] && { dir="$sel"; continue; }
    file_action "$sel"
  done
}

# === App Store ===
install_app() {
  name="$1"; url="$2"; file="$APP_DIR/$(basename "$url")"
  curl -s "$url" -o "$file" && chmod +x "$file"
  dialog --msgbox "$name installed to $file" 6 50
}

uninstall_app() {
  file="$1"
  dialog --yesno "Uninstall $(basename "$file")?" 6 40 && rm -f "$file"
}

app_store_category() {
  cat="$1"
  case "$cat" in
    Games)
      apps=("Steam Upgrade" "https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/new-pi-apps/steam/steam-upgrade.sh")
      ;;
    System)
      apps=("Add to Store" "https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/new-pi-apps/microsoft%20copilot/addtostore.sh")
      ;;
  esac

  menu=()
  for ((i=0; i<${#apps[@]}; i+=2)); do
    name="${apps[i]}"
    url="${apps[i+1]}"
    fname="$APP_DIR/$(basename "$url")"
    [[ -f "$fname" ]] && status="Installed" || status="Install"
    menu+=("$name" "$status")
  done

  dialog --menu "$cat Apps" 15 60 6 "${menu[@]}" 2>"$TMP" || return
  sel=$(<"$TMP")

  for ((i=0; i<${#apps[@]}; i+=2)); do
    if [[ "${apps[i]}" == "$sel" ]]; then
      url="${apps[i+1]}"
      fname="$APP_DIR/$(basename "$url")"
      if [[ -f "$fname" ]]; then
        uninstall_app "$fname"
      else
        install_app "$sel" "$url"
      fi
    fi
  done
}

app_store() {
  dialog --menu "CoolPi App Store" 12 50 3 \
    1 "Games" \
    2 "System Utilities" \
    3 "Back" 2>"$TMP"
  case $(<"$TMP") in
    1) app_store_category "Games" ;;
    2) app_store_category "System" ;;
    *) return ;;
  esac
}

# === App Launcher ===
launch_apps() {
  mapfile -t apps < <(find /usr/share/applications ~/.local/share/applications -name '*.desktop' 2>/dev/null)
  menu=()
  for f in "${apps[@]}"; do
    name=$(grep -m1 "^Name=" "$f" | cut -d= -f2)
    exec=$(grep -m1 "^Exec=" "$f" | cut -d= -f2 | cut -d' ' -f1)
    [[ $name && $exec ]] && menu+=("$exec" "$name")
  done
  dialog --title "Apps" --menu "Launch one:" 20 60 12 "${menu[@]}" 2>"$TMP" || return
  app=$(<"$TMP"); "$app" &
}

