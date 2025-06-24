#!/bin/bash
set -e
LOGFILE="$HOME/steam_install_log.txt"
exec > >(tee -a "$LOGFILE") 2>&1

ANIM_PID=""
RESUME_FLAG="/tmp/steam_resume.flag"
REPO_NAME="BACKUP-PI$RANDOM"
BACKUP_TAR="/tmp/$REPO_NAME.tar.gz"
CLEANUP_PATHS=(~/.steam ~/.local/share/Steam ~/.wine ~/steam_pi_install)

log() {
  echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

cleanup() {
  log "🧹 Cleaning temp files..."
  for p in "${CLEANUP_PATHS[@]}"; do rm -rf "$p"; done
  [ -f "$BACKUP_TAR" ] && rm -f "$BACKUP_TAR"
}

fatal_exit() {
  log "❌ Critical failure. Rebooting..."
  cleanup
  touch "$RESUME_FLAG"
  echo -e "\n⚠️ Steam setup interrupted. After reboot, run:\n   bash steamsetup.sh --resume"
  sudo reboot
}

start_animation() {
  bash -c '
  tput civis
  trap "tput cnorm; exit" SIGINT SIGTERM
  rows=$(tput lines)
  cols=$(tput cols)
  text="DVD"
  len=${#text}
  x=$((RANDOM % (cols - len)))
  y=$((RANDOM % rows))
  dx=1; dy=1; color=31
  while true; do
    load=$(awk "{print \$1}" /proc/loadavg)
    (( $(echo "$load > 1.5" | bc -l) )) && sleep 3 && continue
    tput cup $y $x
    echo -ne "\e[${color}m$text\e[0m"
    sleep 0.05
    tput cup $y $x; echo -ne "   "
    x=$((x + dx)); y=$((y + dy))
    if (( x < 0 || x + len >= cols )); then dx=$(( -dx )); color=$(((color % 6) + 31)); fi
    if (( y < 0 || y >= rows )); then dy=$(( -dy )); color=$(((color % 6) + 31)); fi
  done
  ' &
  ANIM_PID=$!
}

stop_animation() {
  [ -n "$ANIM_PID" ] && kill "$ANIM_PID" 2>/dev/null
  tput cnorm
}

run_step() {
  log "🔧 $1..."
  if eval "$2"; then
    log "✅ Success: $1"
  else
    log "❌ Failed: $1"
    read -rp "Retry this step? (Y/n): " retry
    if [[ "$retry" =~ ^[Yy]$ ]]; then
      cleanup
      eval "$2" || fatal_exit
    else
      fatal_exit
    fi
  fi
}

backup_to_github() {
  read -rp "GitHub username: " GH_USER
  read -s -rp "GitHub PAT (classic, will not show): " GH_TOKEN
  echo

  log "📦 Archiving system files..."
  sudo tar --exclude='*/.cache/*' -czf "$BACKUP_TAR" /etc /home

  log "🐙 Creating private GitHub repo $REPO_NAME..."
  curl -s -H "Authorization: token $GH_TOKEN" \
       -d "{\"name\":\"$REPO_NAME\",\"private\":true}" \
       https://api.github.com/user/repos || fatal_exit

  TMP_DIR=$(mktemp -d)
  cd "$TMP_DIR"
  git init
  git config user.name "PiBackup"
  git config user.email "pi@backup"
  cp "$BACKUP_TAR" .
  git add .
  git commit -m "Emergency backup"
  git remote add origin "https://$GH_TOKEN@github.com/$GH_USER/$REPO_NAME.git"
  git push origin master || fatal_exit
  cd ~
  rm -rf "$TMP_DIR"
  unset GH_TOKEN
  log "✅ Backup complete."
}

delete_backup_repo() {
  [ -z "$GH_USER" ] && return
  [ -z "$GH_TOKEN" ] && return
  curl -X DELETE -H "Authorization: token $GH_TOKEN" \
       "https://api.github.com/repos/$GH_USER/$REPO_NAME"
  log "🧼 Deleted backup repo $REPO_NAME"
}

install_steam() {
  run_step "Removing old installs" "sudo apt purge -y steam wine64 || true && sudo apt autoremove -y"
  run_step "Updating packages" "sudo apt update"
  run_step "Installing Box64/Box86" "sudo apt install -y box64-rpi4arm64 box86-rpi4arm64:armhf"
  run_step "Installing Wine and wget" "sudo apt install -y wine64 wget"
  run_step "Creating Steam directory" "mkdir -p ~/steam_pi_install"
  run_step "Downloading SteamSetup.exe" "wget -O ~/steam_pi_install/SteamSetup.exe https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
  run_step "Running Steam installer" "cd ~/steam_pi_install && wine SteamSetup.exe"
}

# === MAIN ===

if [[ "$1" == "--resume" ]]; then
  log "⚙️ Resuming after reboot..."
  [ ! -f "$RESUME_FLAG" ] && echo "No resume flag found. Exiting." && exit 1
  rm -f "$RESUME_FLAG"
  install_steam
  log "🎉 Installation resumed and completed!"
  exit 0
fi

log "🚀 Starting Steam installer..."

log "🔍 Checking for updates..."
sudo apt update
updates=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || true)
if (( updates > 0 )); then
  echo "📦 $updates packages can be upgraded."
  read -rp "Update now before Steam install? (Y/n): " update_choice
  if [[ "$update_choice" =~ ^[Yy]$ ]]; then
    sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y || log "⚠️ Update failed; continuing..."
  fi
fi

read -rp "🛡️ Create emergency backup to GitHub in case of failure? (Y/n): " do_backup
if [[ "$do_backup" =~ ^[Yy]$ ]]; then
  backup_to_github
fi

# Start animation ONLY after all prompts are finished
start_animation
install_steam
stop_animation

log "🎯 Steam installed! Launch it with:"
echo -e "\nwine ~/.wine/drive_c/Program\\ Files\\ \\(x86\\)/Steam/Steam.exe\n"

read -rp "🧽 Delete GitHub backup repo now? (Y/n): " delete_choice
if [[ "$delete_choice" =~ ^[Yy]$ ]]; then
  delete_backup_repo
fi

log "✅ All done. Log saved to $LOGFILE"
