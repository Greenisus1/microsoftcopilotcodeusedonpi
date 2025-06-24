#!/bin/bash
set -e
LOGFILE="$HOME/steam_install_log.txt"
exec > >(tee -a "$LOGFILE") 2>&1

REPO_NAME="BACKUP-PI$RANDOM"
BACKUP_TAR="/tmp/$REPO_NAME.tar.gz"
CLEANUP_PATHS=(~/.steam ~/.local/share/Steam ~/.wine ~/steam_pi_install)
RESUME_FLAG="/tmp/steam_resume.flag"
ANIM_TAB_TITLE="DVD Bounce"

log() { echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

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

# 🌀 Launch DVD animation in its own terminal tab
launch_dvd_animation_tab() {
  gnome-terminal --tab --title="$ANIM_TAB_TITLE" -- bash -c '
    tput civis
    trap "tput cnorm; exit" SIGINT SIGTERM
    rows=$(tput lines); cols=$(tput cols)
    text="DVD"; len=${#text}
    x=$((RANDOM % (cols - len))); y=$((RANDOM % rows))
    dx=1; dy=1; color=31
    while true; do
      load=$(awk "{print \$1}" /proc/loadavg)
      (( $(echo "$load > 1.5" | bc -l) )) && sleep 2 && continue
      tput cup $y $x; echo -ne "\e[${color}m$text\e[0m"
      sleep 0.05
      tput cup $y $x; echo -ne "   "
      x=$((x + dx)); y=$((y + dy))
      if (( x <= 0 || x + len >= cols )); then dx=$(( -dx )); color=$(((color % 6) + 31)); fi
      if (( y <= 0 || y >= rows )); then dy=$(( -dy )); color=$(((color % 6) + 31)); fi
    done
  '
}

# 🗄️ Optional GitHub backup
backup_to_github() {
  read -rp "GitHub username: " GH_USER
  read -s -rp "GitHub PAT (Classic, will not show): " GH_TOKEN
  echo

  # 🚀 Launch the DVD animation AFTER the token prompt
  launch_dvd_animation_tab &

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

# 🧱 Core install steps
run_step() {
  log "🔧 $1..."
  if eval "$2"; then
    log "✅ Success: $1"
  else
    log "❌ Failed: $1"
    read -rp "Retry this step? (Y/n): " retry
    [[ "$retry" =~ ^[Yy]$ ]] && cleanup && eval "$2" || fatal_exit
  fi
}

install_steam() {
  run_step "Removing old installs" "sudo apt purge -y steam wine64 || true && sudo apt autoremove -y"
  run_step "Updating packages" "sudo apt update"
  run_step "Installing Box64/Box86" "sudo apt install -y box64-rpi4arm64 box86-rpi4arm64:armhf"
  run_step "Installing Wine and wget" "sudo apt install -y wine64 wget"
  run_step "Creating Steam dir" "mkdir -p ~/steam_pi_install"
  run_step "Downloading Steam installer" "wget -O ~/steam_pi_install/SteamSetup.exe https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
  run_step "Running Steam installer" "cd ~/steam_pi_install && wine SteamSetup.exe"
}

# 🏁 Entry point
if [[ "$1" == "--resume" ]]; then
  log "⚙️ Resuming after reboot..."
  [ ! -f "$RESUME_FLAG" ] && echo "No resume flag found. Exiting." && exit 1
  rm -f "$RESUME_FLAG"
  install_steam
  log "🎉 Resumed and completed!"
  exit 0
fi

log "🚀 Starting Steam installer on Raspberry Pi"

read -rp "🛡️ Create emergency GitHub backup before install? (Y/n): " do_backup
[[ "$do_backup" =~ ^[Yy]$ ]] && backup_to_github

install_steam

log "🎯 Steam installed! Launch it with:"
echo -e "\nwine ~/.wine/drive_c/Program\\ Files\\ \\(x86\\)/Steam/Steam.exe\n"
log "✅ Installation complete. Log saved to $LOGFILE"
