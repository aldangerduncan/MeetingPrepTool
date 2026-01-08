#!/bin/bash

# setup_vps.sh
# Run this on your Ubuntu VPS to set up the Meeting Prep tools.

echo "--- Setting up Meeting Prep Tool Environment ---"

# 1. Update and Install Dependencies
echo "[*] Updating apt sources..."
sudo apt-get update -y

echo "[*] Installing dependencies (jq, python3, curl, unzip)..."
sudo apt-get install -y jq python3 python3-pip curl unzip

# 2. Fix Permissions
echo "[*] Making scripts executable..."
chmod +x *.sh *.command *.py

# 3. Timezone Setup (Optional but recommended for cron)
# echo "[*] Checking Timezone..."
# timedatectl

echo "--- Setup Complete! ---"
echo "You can now test the tool by running:"
echo "  ./RunDailyHuddle.command"
echo ""
echo "To set up the daily schedule (Cron), run:"
echo "  crontab -e"
echo "And add a line like:"
echo "  30 7 * * 1-5 cd $PWD && ./RunDailyHuddle.command"
