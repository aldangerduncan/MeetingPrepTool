#!/bin/bash

# Configuration
cd "$(dirname "$0")" || exit 1

TOKEN_FILE=".recent_token"
FM_CREDS_FILE=".fm_creds"
OPENAI_KEY_FILE=".openai_key"
WEB_APP_URL="https://script.google.com/macros/s/AKfycbxhH0lpZ3tq6KZovVQV8UpJubi74EloknJRQzYfDiV7yfAr585sdw_OGNPzCMkzjAlG/exec"

# 1. Get/Refresh Token
if [ -f "$TOKEN_FILE" ]; then
    TOKEN=$(cat "$TOKEN_FILE")
    # FileMaker tokens expire in 15 mins. If older than 10 mins (600s), refresh.
    TOKEN_AGE=$(($(date +%s) - $(stat -f %m "$TOKEN_FILE")))
    if [ "$TOKEN_AGE" -gt 600 ]; then
        echo "[*] Token is old (${TOKEN_AGE}s). Refreshing..."
        if ! ./get_token.sh; then
            echo "[-] Error: Failed to refresh token. Check credentials."
            exit 1
        fi
        TOKEN=$(cat "$TOKEN_FILE")
    fi
else
    echo "[-] No token found. Running get_token.sh..."
    if ! ./get_token.sh; then
        echo "[-] Error: Failed to generate token. Check credentials."
        exit 1
    fi
    TOKEN=$(cat "$TOKEN_FILE")
fi

# 2. Get OpenAI Key
if [ -f "$OPENAI_KEY_FILE" ]; then
    OPENAI_KEY=$(cat "$OPENAI_KEY_FILE" | tr -d '[:space:]')
else
    echo "[-] No OpenAI Key found."
    exit 1
fi

# HTML Header/Style Template (Part 1)
HTML_START="<!DOCTYPE html>
<html lang='en'>
<head>
  <meta charset='UTF-8' />
  <meta name='viewport' content='width=device-width, initial-scale=1.0' />
  <style>
    :root { --bg: #f4f6f8; --card: #ffffff; --text: #2c3e50; --muted: #7f8c8d; --accent: #2980b9; --border: #e0e0e0; }
    body { margin: 0; padding: 32px; font-family: system-ui, -apple-system, sans-serif; background: var(--bg); color: var(--text); }
    .container { max-width: 900px; margin: 0 auto; }
    header { margin-bottom: 32px; }
    h1 { margin: 0; font-size: 2rem; color: var(--text); }
    .date { color: var(--muted); margin-top: 4px; }
    .card { background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 24px; margin-bottom: 24px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
    .card h2 { margin: 0 0 8px 0; font-size: 1.2rem; color: var(--accent); border-bottom: 1px solid #eee; padding-bottom: 8px; }
    .meta-row { display: flex; gap: 12px; margin-bottom: 16px; font-size: 0.9rem; color: var(--muted); }
    .badge { padding: 4px 8px; border-radius: 4px; background: #eee; font-weight: 600; font-size: 0.8rem; }
    .badge.tomato { background: #fadbd8; color: #c0392b; }
    .badge.grape { background: #e8daef; color: #8e44ad; }
    .badge.sage { background: #d5f5e3; color: #27ae60; }
    .content { line-height: 1.6; font-size: 0.95rem; }
    .content p { margin-bottom: 12px; }
    .content ul, .content ol { padding-left: 24px; margin-bottom: 16px; }
    .content li { margin-bottom: 8px; }
    strong { color: #34495e; }
  </style>"

# 3. Fetch Calendar Events
echo "[*] Fetching Today's Meetings..."
CAL_JSON=$(curl -L -s "$WEB_APP_URL")

TODAY_FULL=$(date "+%-d %b %Y")

# Get meeting indices for today
MEETING_COUNT=$(echo "$CAL_JSON" | jq -r --arg today "$TODAY_FULL" '[.events[] | select(.shortDate | startswith($today))] | length')

if [ "$MEETING_COUNT" -eq 0 ]; then
    echo "[-] No external meetings found for today."
    exit 0
fi

# Loop through each meeting
for (( i=0; i<MEETING_COUNT; i++ )); do
    EVT=$(echo "$CAL_JSON" | jq -r --arg today "$TODAY_FULL" --arg i "$i" '[.events[] | select(.shortDate | startswith($today))][$i | tonumber]')
    M_TITLE=$(echo "$EVT" | jq -r '.title')
    M_TIME=$(echo "$EVT" | jq -r '.timeOnly')
    M_COLOR=$(echo "$EVT" | jq -r '.colorId // "default"')
    M_ATTENDEES=$(echo "$EVT" | jq -r '.attendees[] | select(. | contains("irdgroup.com.au") | not)')

    if [ -z "$M_ATTENDEES" ]; then
        echo "[*] Skipping (Internal/No Guest): $M_TITLE"
        continue
    fi

    echo "[*] Processing Meeting: $M_TITLE ($M_TIME)..."
    
    # Create individual HTML for this meeting
    SAFE_TITLE=$(echo "$M_TITLE" | tr -dc '[:alnum:]\n\r' | tr ' ' '_')
    MEETING_HTML_FILE="MeetingPrep_${SAFE_TITLE}_${M_TIME//:/}.html"
    
    cat <<EOF > "$MEETING_HTML_FILE"
$HTML_START
  <title>Meeting Prep: $M_TITLE</title>
</head>
<body>
  <div class='container'>
    <header>
      <h1>Meeting Prep: $M_TITLE</h1>
      <div class="date">$TODAY_FULL at $M_TIME</div>
    </header>
EOF

    # Color Logic for Badge
    TYPE_LABEL="General"
    CSS_CLASS="badge"
    if [ "$M_COLOR" == "11" ]; then TYPE_LABEL="Existing Client"; CSS_CLASS="badge tomato"; 
    elif [ "$M_COLOR" == "3" ]; then TYPE_LABEL="New Business"; CSS_CLASS="badge grape"; 
    elif [ "$M_COLOR" == "2" ]; then TYPE_LABEL="Onboarding"; CSS_CLASS="badge sage"; fi

    # Loop through attendees for THIS meeting
    IFS=$'\n'
    for ATT_EMAIL in $M_ATTENDEES; do
        ATT_EMAIL=$(echo "$ATT_EMAIL" | tr -d '[:space:]')
        echo "    [*] Preparing Person: $ATT_EMAIL..."
        
        # Run Prep Script
        RAW_OUTPUT=$(./meeting_prep.sh "$ATT_EMAIL" "$TOKEN" "$OPENAI_KEY" "$M_COLOR")
        
        # Clean Output
        CLEAN_OUTPUT=$(echo "$RAW_OUTPUT" | grep -v "^\*\*\*" | grep -v "^\[\*\]" | grep -v "^\[+\]" | grep -v "^===" | grep -v "Generating Smart" | grep -v "This might take" | grep -v "^Use the text above" | sed 's/^ //g' | perl -pe 's/\*\*(.*?)\*\*/<strong>$1<\/strong>/g')
        
        # Add Card to Meeting HTML
        cat <<EOF >> "$MEETING_HTML_FILE"
    <div class="card">
      <h2>Briefing: $ATT_EMAIL</h2>
      <div class="meta-row">
        <span class="$CSS_CLASS">$TYPE_LABEL</span>
        <span>$M_TITLE</span>
      </div>
      <div class="content">$CLEAN_OUTPUT</div>
    </div>
EOF
    done

    # Close and Send Email for THIS Meeting
    echo "  </div></body></html>" >> "$MEETING_HTML_FILE"
    
    echo "[*] Sending Email for '$M_TITLE'..."
    HTML_CONTENT=$(cat "$MEETING_HTML_FILE")
    PAYLOAD=$(jq -n --arg html "$HTML_CONTENT" --arg subj "Meeting Prep: $M_TITLE ($M_TIME)" '{html: $html, subject: $subj}')
    curl -L -s -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$WEB_APP_URL" > /dev/null

    # Open local file if requested (and on Mac)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if [ -t 1 ] || [ "$1" == "--open" ]; then
            open "$MEETING_HTML_FILE"
        fi
    fi
done

echo "[*] All reports processed."
