#!/bin/bash
# 📡 Simple Wi-Fi Hotspot Cloner for Raspberry Pi — Terminal UI

HOTSPOT_SSID="PI-HOTSPOT"
ROOT="$HOME/pi-hotspot-logs"
mkdir -p "$ROOT"

clear
echo "📡 Available Wi-Fi Networks:"
mapfile -t nets < <(nmcli -t -f SSID dev wifi | grep -v '^$')
for i in "${!nets[@]}"; do echo "$i) ${nets[$i]}"; done

read -p "Select network number to clone: " idx
SSID="${nets[$idx]}"

if [[ -z "$SSID" ]]; then
  echo "❌ Invalid selection. Aborting."
  exit 1
fi

read -p "Enter password for $SSID: " netpass
echo "🔗 Connecting to upstream: $SSID"
nmcli dev wifi connect "$SSID" password "$netpass"
if [[ $? -ne 0 ]]; then
  echo "❌ Connection failed. Check password or network signal."
  exit 1
fi

read -p "Enter new password for hotspot '$HOTSPOT_SSID': " hotspotpass
IFACE=$(nmcli device status | awk '$2=="wifi"{print $1; exit}')

echo "🚀 Creating hotspot '$HOTSPOT_SSID' on $IFACE..."
nmcli connection delete "$HOTSPOT_SSID" &>/dev/null
nmcli dev wifi hotspot ifname "$IFACE" ssid "$HOTSPOT_SSID" password "$hotspotpass"
if [[ $? -ne 0 ]]; then
  echo "❌ Hotspot failed to launch."
  exit 1
fi

echo -e "\n🧭 Wi-Fi Control Terminal — '$HOTSPOT_SSID' is now active\n"
while true; do
  echo "1) Show connected clients"
  echo "2) Stop hotspot"
  echo "3) Exit"
  read -p "Choose: " choice
  case "$choice" in
    1)
      echo "🔎 Scanning clients..."
      arp -n | grep "$IFACE" | awk '{print "IP: "$1", MAC: "$3}' | tee "$ROOT/clients.log"
      ;;
    2)
      echo "🛑 Stopping hotspot..."
      nmcli connection down "$HOTSPOT_SSID"
      ;;
    3)
      echo "👋 Exiting Wi-Fi control terminal."
      exit 0
      ;;
    *) echo "❌ Invalid choice." ;;
  esac
  echo ""
done
