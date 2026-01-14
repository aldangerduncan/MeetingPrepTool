FM_HOST="https://fms14.filemakerstudio.com.au"
DATABASE="IRD%20Subscribing%20Contacts"
LAYOUT="Subscriber%20Dialogues"  # Correct layout name from meeting_prep.sh
USER="Alex Sheath"

# --- Date Calculation ---
# Allow date override via argument: ./fm_stats.sh "MM/DD/YYYY"
if [ -n "$1" ]; then
    YESTERDAY="$1"
    echo "Using specific date: $YESTERDAY"
else
    # Default to Yesterday (US Format required for FileMaker API)
    # If Today is Monday (1), we want Friday (3 days ago)
    # date +%u returns 1 for Monday
    
    DAY_OF_WEEK=$(date +%u)
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if [ "$DAY_OF_WEEK" -eq 1 ]; then
            YESTERDAY=$(date -v-3d +%m/%d/%Y)
        else
            YESTERDAY=$(date -v-1d +%m/%d/%Y)
        fi
    else
        if [ "$DAY_OF_WEEK" -eq 1 ]; then
            YESTERDAY=$(date -d "last friday" +%m/%d/%Y)
        else
            YESTERDAY=$(date -d "yesterday" +%m/%d/%Y)
        fi
    fi
fi

# echo "Fetching stats for: $YESTERDAY"

# --- Authentication ---
# Reuse the get_token.sh logic or just call it if available
# We'll assume get_token.sh is in the parent dir or we can inline it.
# For now, let's try to source it or reimplement simple auth.

TOKEN_FILE=".recent_token"

# Function to get a fresh token
get_token() {
    # Try silent refresh first (uses saved credentials if available)
    if ./get_token.sh --silent; then
        # echo "[+] Token auto-refreshed." >&2
        return 0
    fi
    
    echo "[-] Token expired and auto-renewal failed."
    echo "    Please run './get_token.sh' manually to re-authenticate and save credentials."
    exit 1
}

# Ensure we have a token
if [ ! -f "$TOKEN_FILE" ]; then
    get_token
fi
TOKEN=$(cat "$TOKEN_FILE")

# echo "DEBUG: Token length: ${#TOKEN}"
if [ ${#TOKEN} -lt 10 ]; then
    echo "ERROR: Token seems invalid/empty."
    exit 1
fi

# --- Query FileMaker ---

# Query for Activity by Alex Sheath on Date
QUERY_JSON=$(cat <<EOF
{
  "query": [
    {
      "Account Manager": "=$USER",
      "Contact Date": "$YESTERDAY"
    }
  ]
}
EOF
)

# echo "Querying FileMaker..."
SEARCH_URL="$FM_HOST/fmi/data/vLatest/databases/$DATABASE/layouts/$LAYOUT/_find"

curl -s -X POST "$SEARCH_URL" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$QUERY_JSON" | python3 sanitize.py > /tmp/fm_daily_stats.json
    
RESPONSE=$(cat /tmp/fm_daily_stats.json)

# Check for errors (e.g., token expired)
# Check for errors (e.g., token expired)
ERR_CODE=$(jq -r '.messages[0].code' /tmp/fm_daily_stats.json)

if [ "$ERR_CODE" == "952" ]; then
    # echo "Token expired. Refreshing..." >&2
    get_token
    TOKEN=$(cat "$TOKEN_FILE")
    curl -s -X POST "$SEARCH_URL" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$QUERY_JSON" | python3 sanitize.py > /tmp/fm_daily_stats.json
        
    RESPONSE=$(cat /tmp/fm_daily_stats.json)
fi

# --- Process Results ---

# Count metrics
# We preserve the JSON response to parse with jq
# We preserve the JSON response to parse with jq
# echo "$RESPONSE" > /tmp/fm_daily_stats.json # Already written

# DEBUG: Print first 500 chars of response to see what's happening
# echo "Raw Response (truncated):"
# echo "$RESPONSE" | head -c 500
# echo ""

# Analyze with JQ
DATA=$(cat /tmp/fm_daily_stats.json)

# Check if data exists
# Check if data exists
MSG_CODE=$(jq -r '.messages[0].code' /tmp/fm_daily_stats.json)
if [ "$MSG_CODE" != "0" ]; then
    echo "No records found or error occurred: $MSG_CODE"
    echo "Stats for $YESTERDAY: 0 Calls, 0 Emails, 0 Meetings."
    exit 0
fi

# Extract Counts
# 1. Outbound Calls: Contact Method == "Phone" (or similar)
# 1. Outbound Calls: Contact Method == "Outbound Call" AND Contact Success starts with "New Business"
CALLS_OUTBOUND=$(jq '[.response.data[] | select(.fieldData["Contact Method"] == "Outbound Call")] | length' /tmp/fm_daily_stats.json)

# 2. Connected Calls: Contact Method == "Phone" AND Contact Success == "Yes" (or "Contact Made")
# Need to verify value list for Contact Success. Assuming "Contact Made" or similar for now.
# 2. Connected Calls: "Outbound Call" AND "New Business" AND Dialogue starts with "sw" (case-insensitive)
CALLS_CONNECTED=$(jq '[.response.data[] | select(.fieldData["Contact Method"] == "Outbound Call" and (.fieldData["Dialogue"] | tostring | test("^sw"; "i")))] | length' /tmp/fm_daily_stats.json)

# 3. Emails Sent: Contact Method == "Email"
# 3. Emails Sent: Contact Method == "Outbound Email" AND Contact Success starts with "New Business"
EMAILS_SENT=$(jq '[.response.data[] | select(.fieldData["Contact Method"] == "Outbound Email")] | length' /tmp/fm_daily_stats.json)

# 4. Meetings Booked (Source: Google Calendar "Created Yesterday")
# We fetch the stats from the Google Apps Script
# Note: get_calendar_events.sh also fetches this, but we need it here for the stats grid.

CAL_URL="https://script.google.com/macros/s/AKfycbxhH0lpZ3tq6KZovVQV8UpJubi74EloknJRQzYfDiV7yfAr585sdw_OGNPzCMkzjAlG/exec"
CAL_JSON=$(curl -L -s "$CAL_URL")

# Extract count from stats object (default to 0 if null)
MEETINGS_BOOKED=$(printf '%s\n' "$CAL_JSON" | jq -r '.stats.createdCount // 0')
if [ $? -ne 0 ] || [ -z "$MEETINGS_BOOKED" ]; then
    MEETINGS_BOOKED="0"
fi

# Helper for stat block
stat_block() {
    echo "<div class=\"stat\">"
    echo "  <div class=\"value\">$1</div>"
    echo "  <div class=\"label\">$2</div>"
    echo "</div>"
}

# 1. Output the Stats Grid
echo "<div class=\"stats-grid\">"
stat_block "$CALLS_OUTBOUND" "Outbound Calls"
stat_block "$CALLS_CONNECTED" "Connected Calls"
stat_block "$EMAILS_SENT" "Emails Sent"
stat_block "$MEETINGS_BOOKED" "Meetings Booked"
echo "</div>"

# 2. Output Detailed Meeting Info (if any)

