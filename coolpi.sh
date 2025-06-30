#!/bin/bash
# coolpi.sh — CoolPi v2.1 all-in-one launcher

#### 1) Self-update in place
REPO="https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/coolpi.sh"
ME="$0"
TMP_UP="/tmp/coolpi_latest.sh"
if command -v curl >/dev/null; then
  curl -s "$REPO" -o "$TMP_UP"
  if [ -s "$TMP_UP" ]; then
    H1=$(sha256sum "$ME"   | cut -d' ' -f1)
    H2=$(sha256sum "$TMP_UP"| cut -d' ' -f1)
    if [ "$H1" != "$H2" ]; then
      mv "$TMP_UP" "$ME"
      chmod +x "$ME"
      exec "$ME" "$@"
    fi
  fi
fi

#### 2) Ensure deps
DEPS=(dialog curl jq base64 sha256sum)
for cmd in "${DEPS[@]}"; do
  if ! command -v "$cmd" >/dev/null; then
    sudo apt update
    sudo apt install -y "$cmd"
  fi
done

#### 3) Globals
TMP="/tmp/coolpi_menu.txt"
APP_DIR="$HOME/coolpi/done-downloads"
GITHUB_API="https://api.github.com"
mkdir -p "$APP_DIR"

#### 4) Banner
show_banner(){
  clear
  cat <<'EOF'
================================
          COOLPI v2.1
 File Manager · App Store · UI
================================
EOF
  sleep 1
}

#### 5) Storage meter
show_storage(){
  mapfile -t D < <(df --output=source,size,used,avail,pcent / | tail -1)
  used=${D[2]}; tot=${D[1]}; free=${D[3]}; pct=${D[4]}
  # convert to blocks
  ub=$(( used*30/tot )); fb=$(( free*30/tot ))
  sb=$(( 30-ub-fb ))
  bar=""
  for i in $(seq 1 $ub); do bar+="\Z1█"; done
  for i in $(seq 1 $sb); do bar+="\Z3█"; done
  for i in $(seq 1 $fb); do bar+="\Z2█"; done
  dialog --colors --title "Storage" --msgbox \
"\nFilesystem: /\n\n$bar\n\n\Z1Used\Z0 | \Z3System\Z0 | \Z2Free\Z0\n$ pct" 12 60
}

#### 6) File actions
delete_file(){
  dialog --yesno "Delete this file?\n\n$1" 7 50 && rm -f "$1"
}
run_file(){
  ext="${1##*.}"
  case "$ext" in
    py) i=python3;;
    sh) i=bash;;
    js) i=node;;
    rb) i=ruby;;
    pl) i=perl;;
    *) dialog --msgbox "No handler for .$ext" 6 40; return;;
  esac
  command -v $i >/dev/null || sudo apt install -y $i
  out=$($i "$1" 2>&1)
  dialog --title "Output" --msgbox "$out" 20 70
}
github_publish(){
  dialog --inputbox "GitHub Token:" 8 60 2>"$TMP"; token=$(<"$TMP")
  dialog --inputbox "Repo (user/repo):" 8 60 2>"$TMP"; repo=$(<"$TMP")
  name=$(basename "$1"); b64=$(base64 < "$1")
  payload=$(jq -nc --arg m "Add $name" --arg c "$b64" '{message:$m,content:$c}')
  http=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT -H "Authorization: token $token" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$GITHUB_API/repos/$repo/contents/$name")
  if [[ "$http" =~ ^20 ]]; then
    dialog --msgbox "Uploaded to $repo" 6 50
  else
    dialog --msgbox "GitHub Error: $http" 6 50
  fi
}
file_action(){
  dialog --menu "File: $(basename "$1")" 12 60 4 \
    1 "Run" \
    2 "Publish to GitHub" \
    3 "Delete" \
    4 "Back" 2>"$TMP"
  case $(<"$TMP") in
    1) run_file "$1";;
    2) github_publish "$1";;
    3) delete_file "$1";;
  esac
}
browse(){
  dir="$1"
  while true; do
    mapfile -t items < <(find "$dir" -maxdepth 1 -mindepth 1 | sort)
    menu=()
    for p in "${items[@]}"; do
      n=$(basename "$p")
      [[ -d $p ]] && n="[DIR] $n"
      menu+=("$p" "$n")
    done
    menu+=("..BACK.." "Return Home")
    dialog --title "Browse: $dir" \
      --menu "Select" 20 70 12 "${menu[@]}" 2>"$TMP" || break
    sel=$(<"$TMP")
    [[ "$sel" == "..BACK.." ]] && break
    [[ -d "$sel" ]] && { dir="$sel"; continue; }
    file_action "$sel"
  done
}

#### 7) App Store
install_app(){
  curl -s "$2" -o "$APP_DIR/$(basename "$2")"
  chmod +x "$APP_DIR/$(basename "$2")"
  dialog --msgbox "$1 installed." 6 50
}
uninstall_app(){
  dialog --yesno "Uninstall $1?" 6 50 && rm -f "$1"
}
app_store_category(){
  case "$1" in
    Games)
      names=("Steam Upgrade")
      urls=("https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/new-pi-apps/steam/steam-upgrade.sh")
      ;;
    "System Utilities")
      names=("Add to Store")
      urls=("https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/new-pi-apps/microsoft%20copilot/addtostore.sh")
      ;;
  esac
  menu=()
  for i in "${!names[@]}"; do
    f="$APP_DIR/$(basename "${urls[i]}")"
    s=$([[ -f $f ]] && echo "Installed" || echo "Install")
    menu+=("${names[i]}" "$s")
  done
  dialog --menu "$1 Apps" 15 60 6 "${menu[@]}" 2>"$TMP" || return
  sel=$(<"$TMP")
  for i in "${!names[@]}"; do
    if [[ "${names[i]}" == "$sel" ]]; then
      f="$APP_DIR/$(basename "${urls[i]}")"
      [[ -f $f ]] && uninstall_app "$f" || install_app "$sel" "${urls[i]}"
    fi
  done
}
app_store(){
  dialog --menu "CoolPi App Store" 12 60 4 \
    1 "Games" \
    2 "System Utilities" \
    3 "Back" 2>"$TMP"
  case $(<"$TMP") in
    1) app_store_category "Games";;
    2) app_store_category "System Utilities";;
  esac
}

#### 8) App Launcher
launch_apps(){
  mapfile -t d < <(find /usr/share/applications ~/.local/share/applications -name '*.desktop' 2>/dev/null)
  menu=()
  for f in "${d[@]}"; do
    name=$(grep -m1 '^Name=' "$f" | cut -d= -f2)
    exe=$(grep -m1 '^Exec=' "$f" | cut -d= -f2 | awk '{print $1}')
    [[ $name && $exe ]] && menu+=("$exe" "$name")
  done
  dialog --menu "Launch App" 20 60 12 "${menu[@]}" 2>"$TMP" || return
  cmd=$(<"$TMP"); "$cmd" &
}

#### 9) System utilities
system_utils(){
  dialog --menu "System Tools" 12 50 4 \
    1 "Reboot" \
    2 "Shutdown" \
    3 "Storage" \
    4 "Back" 2>"$TMP"
  case $(<"$TMP") in
    1) sudo reboot;;
    2) sudo shutdown now;;
    3) show_storage;;
  esac
}

#### 10) Main menu
main_menu(){
  while true; do
    dialog --title "CoolPi Home" --menu "Choose:" 15 60 6 \
      1 "Browse Files" \
      2 "Launch Apps" \
      3 "System Utilities" \
      4 "App Store" \
      5 "Exit" 2>"$TMP"
    case $(<"$TMP") in
      1) browse "$HOME";;
      2) launch_apps;;
      3) system_utils;;
      4) app_store;;
      5) clear; exit 0;;
    esac
  done
}

# Launch
show_banner
main_menu
