
  echo "============================================================"
  echo "   _____ _                                 _  __ _           "
  echo "  / ____| |                               (_)/ _(_)          "
  echo " | (___ | |_ _ __ ___  __ _ _ __ ___   ___ _| |_ _  ___ ___  "
  echo "  \___ \| __| '__/ _ \/ _\` | '_ \` _ \ / _ \ |  _| |/ __/ _ \ "
  echo "  ____) | |_| | |  __/ (_| | | | | | |  __/ | | | | (_|  __/ "
  echo " |_____/ \__|_|  \___|\__,_|_| |_| |_|\___|_|_| |_|\___\___| "
  echo "                                                             "
  echo "                  STEAMFIXER [BETA]                          "
  echo "        UPDATING IN PROGRESS MAY TAKE 5 MINUITS              "
  echo "============================================================"



wget https://raw.githubusercontent.com/Greenisus1/microsoftcopilotcodeusedonpi/main/new-pi-apps/steam/steam-upgrade.sh
chmod +x steam-upgrade.sh
sudo mv steam-upgrade.sh /usr/local/bin/steamfixer
./steam-upgrade.sh
  echo "====================OPENING UPDATED STEAMFIXER==================="
  echo "ERROR 4019"
  echo "close tab and run "steamfixer"

