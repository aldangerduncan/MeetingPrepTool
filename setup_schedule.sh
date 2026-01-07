#!/bin/bash

# Setup Cron Job for Daily Huddle
# Schedule: 07:00 AM, Mon-Fri

# Resolve absolute path to the directory where this script is located
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMMAND_PATH="$DIR/RunDailyHuddle.command"

# Check if command exists
if [ ! -f "$COMMAND_PATH" ]; then
    echo "Error: Could not find command at $COMMAND_PATH"
    exit 1
fi

# Ensure executable
chmod +x "$COMMAND_PATH"

# Cron line
# 0 7 * * 1-5  = 7:00 AM, Mon-Fri
# Redirect stdout/stderr to a log file for debugging
LOG_FILE="/tmp/daily_huddle_cron.log"
CRON_JOB="0 7 * * 1-5 $COMMAND_PATH >> $LOG_FILE 2>&1"

# Check if job already exists
(crontab -l 2>/dev/null | grep -F "$COMMAND_PATH") && echo "Job already scheduled." && exit 0

# Add job
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "Success! Daily Huddle scheduled for 7:00 AM Mon-Fri."
echo "Logs will be written to: $LOG_FILE"
echo ""
echo "IMPORTANT: On macOS, you may need to grant 'Full Disk Access' to /usr/sbin/cron"
echo "Go to System Settings > Privacy & Security > Full Disk Access"
echo "If 'cron' is not listed, click '+' and add /usr/sbin/cron (cmd+shift+G to find it)."
