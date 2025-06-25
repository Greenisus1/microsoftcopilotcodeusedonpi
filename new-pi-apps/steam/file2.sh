#!/bin/bash
# FULL BACKUP + RECOVERY DETECTION SCRIPT
set -e
BACKUP_ID=$((1000 + RANDOM % 9000))
REPO_NAME="BACKUP-PI$BACKUP_ID"
BACKUP_TAR="/tmp/$REPO_NAME.tar.gz"
RESTORE_NOTE="/tmp/RESTORE_FLAG_DETECTED"
ARCHIVE_TEMP="/tmp/full_pi_backup"
INSTRUCTIONS="restore_instructions.txt"

echo -e "\n🚨 Full Pi Backup Script Activated."

# Check if previously restored
if [ -f "$RESTORE_NOTE" ]; then
  echo "⚠️  Warning: This system was previously restored from backup."
  read -p "Do you want to continue and overwrite another full backup? (y/N): " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

# Step 1: Ask for GitHub creds
read -rp "🧑 GitHub username: " GH_USER
read -s -rp "🔑 GitHub Personal Access Token (Classic): " GH_TOKEN
echo

# Step 2: Archive everything except volatile mounts
echo -e "\n📦 Archiving entire system (excluding /proc, /sys, etc)..."
sudo mkdir -p "$ARCHIVE_TEMP"
cd "$ARCHIVE_TEMP"
sudo tar --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run \
         --exclude=/media --exclude=/mnt --exclude=/tmp \
         -czpf "$BACKUP_TAR" /

# Step 3: Create restore instructions
cat > "$ARCHIVE_TEMP/$INSTRUCTIONS" <<EOF
🚀 Restore Instructions for $REPO_NAME

1. Clone the backup repository:
   git clone https://github.com/$GH_USER/$REPO_NAME.git

2. Extract the backup archive:
   sudo tar -xvpf $REPO_NAME.tar.gz -C /

3. Reboot your Pi:
   sudo reboot

⚠️ This will overwrite existing system files with those from the backup.
Use with caution.
EOF

# Step 4: Push to GitHub
echo -e "\n🐙 Creating GitHub repo $REPO_NAME..."
curl -s -H "Authorization: token $GH_TOKEN" \
     -d "{\"name\":\"$REPO_NAME\",\"private\":true}" \
     https://api.github.com/user/repos > /dev/null

echo "📤 Uploading archive and instructions..."
cd "$ARCHIVE_TEMP"
git init -q
git config user.name "PiAutoBackup"
git config user.email "pi@autobackup"
git add .
git commit -m "📦 Backup snapshot $REPO_NAME"
git remote add origin "https://$GH_TOKEN@github.com/$GH_USER/$REPO_NAME.git"
git push -q origin master

# Step 5: Flag as restored system if ever used for recovery
touch "$RESTORE_NOTE"

# Cleanup
echo -e "\n✅ Backup complete. Private repo: https://github.com/$GH_USER/$REPO_NAME"
rm -rf "$ARCHIVE_TEMP"
unset GH_TOKEN
