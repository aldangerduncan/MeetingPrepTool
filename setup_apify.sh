#!/bin/bash

KEY_FILE=".apify_key"

echo "--- Apify API Token Setup ---"
echo "This token will be used to scrape LinkedIn profiles for meeting briefings."
echo ""

# Prompt for key safely
read -s -p "Enter your Apify API Token: " API_KEY
echo ""

if [ -z "$API_KEY" ]; then
    echo "[-] Error: Token cannot be empty."
    exit 1
fi

# Save to file
echo "$API_KEY" > "$KEY_FILE"
echo "[+] Token saved to $KEY_FILE"
echo ""
echo "You can now run ./MeetingPrep.command (or ./meeting_prep.sh) and it will use this token."
