#!/bin/bash

# CloudKeyContact.command
# Triggers the VPS "email_meeting_prep.sh" script via SSH
# Useful for running the tool on the VPS (bypassing local firewalls) but triggering it from a Mac.

# 1. Get Input via GUI (Mac specific)
QUERY=$(osascript -e "text returned of (display dialog \"Who are you meeting with?\" default answer \"\" buttons {\"OK\", \"Cancel\"} default button \"OK\" with title \"Cloud Meeting Prep\")")

if [ -z "$QUERY" ]; then
    exit 0
fi

echo "--- Cloud Meeting Prep ---"
echo "Target: $QUERY"
echo "Connecting to VPS (74.208.72.121)..."
echo "(Please enter your VPS Password if asked)"

# 2. Run Remote Command
# -t forces a pseudo-terminal so sudo/password prompts work if needed (though usually ssh passes auth before command)
# We change directory to ensuring finding the script and keys
ssh -t root@74.208.72.121 "cd /root/MeetingPrep && ./email_meeting_prep.sh \"$QUERY\""

echo ""
echo "--- Done ---"
echo "Check your email for the report."
# Keep window open for a moment so user can see result
sleep 5
