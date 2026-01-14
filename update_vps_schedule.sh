#!/bin/bash

# remote_update.sh
# This script connects to the VPS to:
# 1. Pull the latest code (including the updated setup instructions)
# 2. Configure the Cron job for the Meeting Prep Tool (8:00 AM)
# 3. Run the Meeting Prep tool immediately for today's meetings

HOST="74.208.72.121"
USER="root"
DIR="MeetingPrep"

echo "--- Connecting to VPS ($HOST) ---"
echo "You may be asked for your VPS password."

ssh -A "$USER@$HOST" "bash -s" <<EOF
    # 1. Update Code
    echo "[VPS] Updating Codebase..."
    cd $DIR || exit 1
    git fetch origin
    git reset --hard origin/main
    
    # 2. Set Permissions
    chmod +x *.sh *.command *.py
    
    # 3. Update Cron Job (Idempotent)
    echo "[VPS] Configuring Cron Job for 8:00 AM..."
    CRON_CMD="0 8 * * 1-5 cd \$PWD && ./prep_todays_meetings.sh >> /tmp/meeting_prep.log 2>&1"
    
    # Check if job already exists to avoid duplicates
    if crontab -l 2>/dev/null | grep -F "prep_todays_meetings.sh" >/dev/null; then
        echo "[VPS] Cron job already exists. Skipping."
    else
        (crontab -l 2>/dev/null; echo "\$CRON_CMD") | crontab -
        echo "[VPS] Cron job added."
    fi
    
    # 4. Run Immediately
    echo "[VPS] Executing Meeting Prep for Today..."
    ./prep_todays_meetings.sh
    
    echo "[VPS] Done."
EOF
