#!/bin/bash

# remote_update.sh
# This script connects to the VPS to:
# 1. Pull the latest code (including the updated setup instructions)
# 2. Configure the Cron job for the Meeting Prep Tool (8:00 AM)
# 3. Run the Meeting Prep tool immediately for today's meetings

HOST="216.250.118.221"
USER="root"
DIR="MeetingPrep"

echo "--- Connecting to VPS ($HOST) ---"
echo "You may be asked for your VPS password."

# 0. Sync Secrets
echo "[Local] Copying credentials to VPS..."
scp .fm_creds .openai_key .apify_key "$USER@$HOST:$DIR/" 2>/dev/null || echo "[!] Warning: Some credential files could not be copied (they may not exist locally)."

ssh -A "$USER@$HOST" "bash -s" <<EOF
    # 0. Set Timezone
    echo "[VPS] Setting timezone to Australia/Sydney..."
    timedatectl set-timezone Australia/Sydney
    echo "[VPS] Current time: \$(date)"

    # 1. Update Code
    echo "[VPS] Updating Codebase..."
    cd $DIR || exit 1
    git fetch origin
    git reset --hard origin/main
    
    # 2. Set Permissions
    chmod +x *.sh *.command *.py
    
    # 3. Update Cron Job (Idempotent)
    echo "[VPS] Configuring Cron Job for 8:00 AM..."
    SCRIPT_DIR=\$(pwd)
    HUDDLE_CMD="30 7 * * 1-5 cd \$SCRIPT_DIR && ./RunDailyHuddle.command >> /tmp/daily_huddle.log 2>&1"
    PREP_CMD="0 8 * * 1-5 cd \$SCRIPT_DIR && ./prep_todays_meetings.sh >> /tmp/meeting_prep.log 2>&1"

    # Rebuild crontab cleanly (remove old entries, add fresh ones)
    crontab -l 2>/dev/null | grep -v "RunDailyHuddle\|prep_todays_meetings" | { cat; echo "\$HUDDLE_CMD"; echo "\$PREP_CMD"; } | crontab -
    echo "[VPS] Cron entries:"
    echo "  \$HUDDLE_CMD"
    echo "  \$PREP_CMD"
    
    # 4. Run Immediately
    echo "[VPS] Executing Meeting Prep for Today..."
    ./prep_todays_meetings.sh
    
    echo "[VPS] Done."
EOF
