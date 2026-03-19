#!/bin/bash

# Installs a macOS LaunchAgent to auto-pull from GitHub on login and every hour.
# Run once on any machine where the repo is cloned.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_PATH="$(which git)"
PLIST_LABEL="com.meetingpreptool.gitpull"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
LOG_DIR="$HOME/Library/Logs"

if [ -z "$GIT_PATH" ]; then
  echo "[-] Error: git not found. Install Xcode Command Line Tools first."
  exit 1
fi

echo "[*] Installing LaunchAgent..."
echo "    Repo: $REPO_DIR"
echo "    Git:  $GIT_PATH"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${GIT_PATH}</string>
        <string>-C</string>
        <string>${REPO_DIR}</string>
        <string>pull</string>
        <string>origin</string>
        <string>main</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/meetingpreptool-sync.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/meetingpreptool-sync.log</string>
</dict>
</plist>
EOF

# Unload first if already exists, then load
launchctl unload "$PLIST_PATH" 2>/dev/null
launchctl load "$PLIST_PATH"

echo "[+] Done. The repo will now auto-pull on login and every hour."
echo "    Log: $LOG_DIR/meetingpreptool-sync.log"
