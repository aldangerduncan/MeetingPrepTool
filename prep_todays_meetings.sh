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
    if [[ "$OSTYPE" == "darwin"* ]]; then
        FILE_MTIME=$(stat -f %m "$TOKEN_FILE")
    else
        FILE_MTIME=$(stat -c %Y "$TOKEN_FILE")
    fi
    TOKEN_AGE=$(($(date +%s) - FILE_MTIME))
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

# Email-safe HTML shell (head + body open). Each brief is self-contained.
HTML_START='<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<meta name="x-apple-disable-message-reformatting" />
<meta name="color-scheme" content="light" />
<meta name="supported-color-schemes" content="light" />
<!--[if mso]>
<noscript><xml><o:OfficeDocumentSettings><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml></noscript>
<![endif]-->
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet" />
<style type="text/css">
  body, table, td, a { -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%; }
  table, td { mso-table-lspace: 0pt; mso-table-rspace: 0pt; }
  img { -ms-interpolation-mode: bicubic; border: 0; }
  body { margin: 0 !important; padding: 0 !important; width: 100% !important; }
  @media screen and (max-width: 620px) {
    .container { width: 100% !important; }
    .px { padding-left: 20px !important; padding-right: 20px !important; }
    .meta-cell { display: block !important; width: 100% !important; box-sizing: border-box; border-right: 0 !important; border-bottom: 1px solid #e6e8ec !important; }
    .meta-cell:last-child { border-bottom: 0 !important; }
    .kv-label, .kv-value { display: block !important; width: 100% !important; }
    .move-label, .move-value { display: block !important; width: 100% !important; }
    h1.brief-h1 { font-size: 28px !important; line-height: 1.15 !important; }
  }
</style>'

# 3. Fetch Calendar Events
echo "[*] Fetching Today's Meetings..."
CAL_JSON=$(curl -L -s "$WEB_APP_URL")

TODAY_FULL=$(TZ=Australia/Sydney date "+%-d %b %Y")

# Get meeting indices for today
MEETING_COUNT=$(echo "$CAL_JSON" | jq -r --arg today "$TODAY_FULL" '[.events[] | select(.shortDate | startswith($today))] | length')

if [ "$MEETING_COUNT" -eq 0 ]; then
    echo "[-] No external meetings found for today."
    exit 0
fi

# Send OTP setup request to client services with all external attendees for today
EXTERNAL_EMAILS=$(echo "$CAL_JSON" | jq -r --arg today "$TODAY_FULL" '
    [.events[] | select(.shortDate | startswith($today)) | .attendees[]?]
    | map(select(contains("irdgroup.com.au") | not))
    | unique
    | .[]
')

if [ -n "$EXTERNAL_EMAILS" ]; then
    echo "[*] Sending OTP setup request to clientservices@irdgroup.com.au..."
    OTP_LIST=$(echo "$EXTERNAL_EMAILS" | sed 's|.*|<li>&</li>|' | tr -d '\n')
    OTP_HTML="<p>Hi guys can please set up a OTP for the following clients I'm due to meet with today:</p><ul>${OTP_LIST}</ul>"
    OTP_PAYLOAD=$(jq -n \
        --arg html "$OTP_HTML" \
        --arg subj "OTP setup request — clients meeting today" \
        --arg to "clientservices@irdgroup.com.au" \
        '{html: $html, subject: $subj, to: $to}')
    curl -L -s -X POST -H "Content-Type: application/json" -d "$OTP_PAYLOAD" "$WEB_APP_URL" > /dev/null
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
<body style="margin:0; padding:0; background-color:#f5f6f8; color:#1a1d21;">
<div style="display:none; max-height:0; overflow:hidden; mso-hide:all; font-size:1px; line-height:1px; color:#f5f6f8;">Meeting prep for $M_TITLE at $M_TIME</div>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" bgcolor="#f5f6f8" style="background-color:#f5f6f8;">
<tr><td align="center" style="padding:32px 16px;">
EOF

    # Loop through attendees for THIS meeting — each brief is self-contained
    IFS=$'\n'
    for ATT_EMAIL in $M_ATTENDEES; do
        ATT_EMAIL=$(echo "$ATT_EMAIL" | tr -d '[:space:]')
        echo "    [*] Preparing Person: $ATT_EMAIL..."

        # Re-read token in case it was refreshed by a previous iteration
        if [ -f "$TOKEN_FILE" ]; then
            TOKEN=$(cat "$TOKEN_FILE")
        fi

        # meeting_prep.sh returns the rendered brief container HTML on stdout
        ./meeting_prep.sh "$ATT_EMAIL" "$TOKEN" "$OPENAI_KEY" "$M_COLOR" >> "$MEETING_HTML_FILE"
    done

    # Close email
    echo "</td></tr></table></body></html>" >> "$MEETING_HTML_FILE"
    
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
