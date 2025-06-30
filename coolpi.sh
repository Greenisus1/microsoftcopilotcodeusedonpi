#!/bin/bash
# coolpi.sh — CoolPi v2.3: Self-Updating UI + update-coolpi Command

#### GLOBALS & PATHS
ME="$(readlink -f "$0")"
NAME="$(basename "$0")"
REPO="https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/coolpi.sh"
TMP_UP="/tmp/coolpi_latest.sh"
TMP_MENU="/tmp/coolpi_menu.txt"
APP_DIR="$HOME/coolpi/done-downloads"
GITHUB_API="https://api.github.com"
mkdir -p "$APP_DIR"

#### 1) Quick-update mode
# If the script is invoked as 'update-coolpi', skip the UI and just update.
if [[ "$NAME" == "update-coolpi" ]]; then
  echo "Updating CoolPi..."
  curl -fsSL "$REPO" -o "$ME" \
    && chmod +x "$ME" \
    && echo "Updated at $(date)." \
    || echo "Update failed."
  exit
fi

#### 2) Ensure update-coolpi symlink exists
if ! command -v update-coolpi &>/dev/null; then
  sudo ln -sf "$ME" /usr/local/bin/update-coolpi 2>/dev/null
fi

#### 3) Self-Updater (normal launch)
if command -v curl &>/dev/null; then
  curl -fsSL "$REPO" -o "$TMP_UP"
  if [ -s "$TMP_UP" ]; then
    H1=$(sha256sum "$ME"    | cut -d' ' -f1)
    H2=$(sha256sum "$TMP_UP"| cut -d' ' -f1)
    if [[ "$H1" != "$H2" ]]; then
      mv "$TMP_UP" "$ME"
      chmod +x "$ME"
      exec "$ME" "$@"
    fi
  fi
fi

#### 4) Dependencies
DEPS=(dialog curl jq base64 sha256sum)
for cmd in "${DEPS[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    sudo apt update && sudo apt install -y "$cmd"
  fi
done

#### 5) UI Banners & Helpers
show_banner(){
  clear
  cat <<'EOF'
=======================================
             COOLPI v2.3               
  File Manager · App Store · Shell    
=======================================
EOF
  sleep 1
}

show_storage(){
  read size used avail pct <<<$(df --output=size,used,avail,pcent / | tail -1)
  ub=$(( used*30/size )); fb=$(( avail*30/size ))
  sb=$(( 30-ub-fb )); bar=""
  for i in $(seq 1 $ub); do bar+="\Z1█"; done
  for i in $(seq 1 $sb); do bar+="\Z3█"; done
  for i in $(seq 1 $fb); do bar+="\Z2█"; done
  dialog --colors --title "Storage" --msgbox \
"\n/ Usage: $pct\n\n$bar\n\n\Z1Used\Z0 | \Z3System\Z0 | \Z2Free\Z0" 12 60
}

embedded_shell(){
  dialog --msgbox "Entering subshell. Use Ctrl+Shift+C/V to copy/paste." 6 60
  clear
  PS1="CoolPi> " bash --norc --noprofile
}

#### 6) File-manager
delete_file(){ dialog --yesno "Delete this file?\n\n$1" 7 50 && rm -f "$1"; }
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
  command -v $i &>/dev/null || sudo apt install -y $i
  out=$($i "$1" 2>&1)
  dialog --title "Output" --msgbox "$out" 20 70
}
github_publish(){
  dialog --inputbox "GitHub Token:" 8 60 2>"$TMP_MENU"; token=$(<"$TMP_MENU")
  dialog --inputbox "Repo (user/repo):" 8 60 2>"$TMP_MENU"; repo=$(<"$TMP_MENU")
  name=$(basename "$1"); b64=$(base64 < "$1")
  payload=$(jq -nc --arg m "Add $name" --arg c "$b64" '{message:$m,content:$c}')
  http=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT -H "Authorization: token $token" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$GITHUB_API/repos/$repo/contents/$name")
  if [[ "$http" =~ ^20 ]]; then dialog --msgbox "Uploaded." 6 50
  else dialog --msgbox "GitHub Error: $http" 6 50; fi
}
file_action(){
  dialog --menu "File: $(basename "$1")" 12 50 4 \
    1 "Run" 2 "Publish" 3 "Delete" 4 "Back" 2>"$TMP_MENU"
  case $(<"$TMP_MENU") in
    1) run_file "$1";;
    2) github_publish "$1";;
    3) delete_file "$1";;
  esac
}
browse(){
  dir="${1:-$HOME}"
  while true; do
    mapfile -t items < <(find "$dir" -maxdepth 1 -mindepth 1 | sort)
    menu=()
    for p in "${items[@]}"; do
      n=$(basename "$p"); [[ -d $p ]] && n="[DIR] $n"
      menu+=("$p" "$n")
    done
    menu+=("..BACK.." "Return Home")
    dialog --title "Browse: $dir" \
      --menu "Select" 20 70 12 "${menu[@]}" 2>"$TMP_MENU" || break
    sel=$(<"$TMP_MENU")
    [[ "$sel" == "..BACK.." ]] && break
    [[ -d "$sel" ]] && { dir="$sel"; continue; }
    file_action "$sel"
  done
}

#### 7) App-Store
install_app(){ curl -fsSL "$2" -o "$APP_DIR/$(basename "$2")"; chmod +x "$APP_DIR/$(basename "$2")"; dialog --msgbox "'$1' installed." 6 50; }
uninstall_app(){ dialog --yesno "Uninstall $1?" 6 50 && rm -f "$1"; }

app_store_category(){
  case "$1" in
    Games)
      names=(Steam\ Upgrade SuperTux \(0AD\) ScratchTerminal Colobot FreeCiv)
      urls=(
        https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/new-pi-apps/steam/steam-upgrade.sh
        https://raw.githubusercontent.com/lucasrolff/SuperTuxPImenu/master/install-supertux.sh
        https://raw.githubusercontent.com/play0ad/0ad/master/tools/deploy/run-0ad.sh
        https://raw.githubusercontent.com/llSourcell/scratch-terminal/master/scratch-terminal.sh
        https://raw.githubusercontent.com/danilofreire/colobot-calpha/master/install-colobot.sh
        https://raw.githubusercontent.com/Freeciv/freeciv/master/tools/freeciv-install.sh
      ) ;;
    "System Utilities")
      names=(AddToStore CLIWeather Neofetch bat htop ncdu)
      urls=(
        https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/new-pi-apps/microsoft%20copilot/addtostore.sh
        https://raw.githubusercontent.com/schachne/cli-weather/master/cli-weather.sh
        https://raw.githubusercontent.com/dylanaraps/neofetch/master/neofetch
        https://raw.githubusercontent.com/sharkdp/bat/master/assets/install.sh
        https://raw.githubusercontent.com/hishamhm/htop/master/htop.sh
        https://raw.githubusercontent.com/rofl0r/binwalk/master/scripts/install-ncdu.sh
      ) ;;
    Productivity)
      names=(micro ranger taskwarrior)
      urls=(
        https://raw.githubusercontent.com/zyedidia/micro/master/scripts/install.sh
        https://raw.githubusercontent.com/ranger/ranger/master/install/ranger-installer.sh
        https://raw.githubusercontent.com/GothenburgBitFactory/taskwarrior/master/install.sh
      ) ;;
    Development)
      names=(git nodejs python3 tmux)
      urls=(
        https://raw.githubusercontent.com/git-guides/install-git/master/install.sh
        https://raw.githubusercontent.com/nodesource/distributions/master/deb/setup_14.x
        https://raw.githubusercontent.com/pyenv/pyenv-installer/master/bin/pyenv-installer
        https://raw.githubusercontent.com/tmux/tmux/master/install/install_tmux.sh
      ) ;;
  esac

  menu=()
  for i in "${!names[@]}"; do
    f="$APP_DIR/$(basename "${urls[i]}")"
    s=$([[ -f $f ]] && echo "Installed" || echo "Install")
    menu+=("${names[i]}" "$s")
  done

  dialog --menu "$1 Apps" 16 60 6 "${menu[@]}" 2>"$TMP_MENU" || return
  sel=$(<"$TMP_MENU")
  for i in "${!names[@]}"; do
    if [[ "${names[i]}" == "$sel" ]]; then
      f="$APP_DIR/$(basename "${urls[i]}")"
      [[ -f $f ]] && uninstall_app "$f" || install_app "$sel" "${urls[i]}"
    fi
  done
}

app_store(){
  dialog --menu "CoolPi App Store" 15 60 5 \
    1 "Games" \
    2 "System Utilities" \
    3 "Productivity" \
    4 "Development" \
    5 "Back" 2>"$TMP_MENU"
  case $(<"$TMP_MENU") in
    1) app_store_category "Games";;
    2) app_store_category "System Utilities";;
    3) app_store_category "Productivity";;
    4) app_store_category "Development";;
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
  dialog --menu "Launch App" 20 60 12 "${menu[@]}" 2>"$TMP_MENU" || return
  cmd=$(<"$TMP_MENU"); "$cmd" &
}

#### 9) System Tools
system_utils(){
  dialog --menu "System Utilities" 12 60 5 \
    1 "Reboot" \
    2 "Shutdown" \
    3 "Storage" \
    4 "Shell" \
    5 "Back" 2>"$TMP_MENU"
  case $(<"$TMP_MENU") in
    1) sudo reboot;;
    2) sudo shutdown now;;
    3) show_storage;;
    4) embedded_shell;;
  esac
}

#### 10) Main Menu
main_menu(){
  while true; do
    dialog --title "CoolPi Home" --menu "Select:" 15 60 6 \
      1 "Browse Files" \
      2 "Launch Apps" \
      3 "System Utilities" \
      4 "App Store" \
      5 "Exit" 2>"$TMP_MENU"
    case $(<"$TMP_MENU") in
      1) browse "$HOME";;
      2) launch_apps;;
      3) system_utils;;
      4) app_store;;
      5) clear; exit 0;;
    esac
  done
}

#### START
show_banner
main_menu
