#!/bin/bash
# LemonTest: A light, citrusy speedtest wrapper

echo "🍋 Running LemonTest..."
echo "-----------------------------"

# Check if speedtest CLI is installed
if ! command -v speedtest &> /dev/null; then
    echo "Speedtest CLI not found. Installing via curl..."
    curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
    sudo apt-get install speedtest -y
fi

# Run the test silently
result=$(speedtest --accept-license --accept-gdpr -f json)

# Extract values using jq
ping=$(echo "$result" | jq '.ping.latency')
download=$(echo "$result" | jq '.download.bandwidth')
upload=$(echo "$result" | jq '.upload.bandwidth')

# Convert bandwidth from bits/sec to Mbps
dl_mbps=$(awk "BEGIN {printf \"%.2f\", $download / 125000}")
ul_mbps=$(awk "BEGIN {printf \"%.2f\", $upload / 125000}")

echo "Ping: $ping ms"
echo "Download: $dl_mbps Mbps"
echo "Upload: $ul_mbps Mbps"
echo "-----------------------------"
echo "🍋 LemonTest complete!"

# Optional: log results to a file
echo "$(date): Ping $ping ms, Download $dl_mbps Mbps, Upload $ul_mbps Mbps" >> lemontest.log

