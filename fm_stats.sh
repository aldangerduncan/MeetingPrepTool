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
    if [[ "$OSTYPE" == "darwin"* ]]; then
        YESTERDAY=$(date -v-1d +%m/%d/%Y)
    else
        YESTERDAY=$(date -d "yesterday" +%m/%d/%Y)
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
        echo "[+] Token auto-refreshed."
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
    echo "Token expired. Refreshing..."
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
CALLS_OUTBOUND=$(jq '[.response.data[] | select(.fieldData["Contact Method"] == "Outbound Call" and (.fieldData["Contact Success"] | tostring | startswith("New Business")))] | length' /tmp/fm_daily_stats.json)

# 2. Connected Calls: Contact Method == "Phone" AND Contact Success == "Yes" (or "Contact Made")
# Need to verify value list for Contact Success. Assuming "Contact Made" or similar for now.
# 2. Connected Calls: "Outbound Call" AND "New Business" AND Dialogue starts with "sw" (case-insensitive)
CALLS_CONNECTED=$(jq '[.response.data[] | select(.fieldData["Contact Method"] == "Outbound Call" and (.fieldData["Contact Success"] | tostring | startswith("New Business")) and (.fieldData["Dialogue"] | tostring | test("^sw"; "i")))] | length' /tmp/fm_daily_stats.json)

# 3. Emails Sent: Contact Method == "Email"
# 3. Emails Sent: Contact Method == "Outbound Email" AND Contact Success starts with "New Business"
EMAILS_SENT=$(jq '[.response.data[] | select(.fieldData["Contact Method"] == "Outbound Email" and (.fieldData["Contact Success"] | tostring | startswith("New Business")))] | length' /tmp/fm_daily_stats.json)

# 4. Meetings Booked: 
# Logic: Contact Success starts with "New Business" AND (Action Item is "Arrange/Conduct Meeting" OR Contact Success contains "meeting")
# "Meeting Booked" implies New Business per user request.
MEETINGS_BOOKED=$(jq '[.response.data[] | select((.fieldData["Contact Success"] | tostring | startswith("New Business")) and ((.fieldData["Contact Success"] | tostring | test("meeting"; "i")) or .fieldData["Action_Item"] == "Arrange Meeting" or .fieldData["Action_Item"] == "Conduct Meeting"))] | length' /tmp/fm_daily_stats.json)

# Helper for stat block
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
if [ "$MEETINGS_BOOKED" -gt 0 ]; then
    echo "<div style=\"margin-top:24px; border-top:1px solid #eee; padding-top:16px;\">"
    echo "  <h3 style=\"margin:0 0 12px; font-size:0.9rem; color:#7f8c8d; text-transform:uppercase; letter-spacing:0.05em;\">Booked Meetings Detail</h3>"
    
    # Extract details using jq
    # Extract details using jq
    # Filter matches MEETINGS_BOOKED logic
    jq -r '
      .response.data[] 
      | select((.fieldData["Contact Success"] | tostring | startswith("New Business")) and ((.fieldData["Contact Success"] | tostring | test("meeting"; "i")) or .fieldData["Action_Item"] == "Arrange Meeting" or .fieldData["Action_Item"] == "Conduct Meeting"))
      | "<div class=\"calendar-item\">
           <div class=\"calendar-time\">Booked</div>
           <div>" + .fieldData["IRD Subscribing Contacts 4::First Name"] + " " + .fieldData["IRD Subscribing Contacts 4::Surname"] + " (" + .fieldData.Company + ")</div>
           <div class=\"calendar-meta\">" + .fieldData["IRD Subscribing Contacts 4::Email"] + "</div>
         </div>"
    ' /tmp/fm_daily_stats.json

    echo "</div>"
fi
