#!/bin/bash

# Configuration
HOST="https://fms14.filemakerstudio.com.au"
DATABASE="IRD Subscribing Contacts"
DEFAULT_TOKEN="dcc790a415765bc93c3d1d2a5060a00438e554c6f6cef153754b"

QUERY="$1"
TOKEN="${2:-$DEFAULT_TOKEN}"
OPENAI_KEY="$3"
COLOR_ID="$4"

if [ -z "$QUERY" ]; then
  echo "Usage: ./meeting_prep.sh \"Name or Email\" [Token]"
  exit 1
fi

LOG_FILE="/tmp/meeting_prep_debug.log"

log() {
  echo "$1" >> "$LOG_FILE"
}

# Helper to URL encode (minimal)
urlencode() {
  # jq can url encode
  echo "$1" | jq -Rr @uri
}

LAYOUT_CONTACTS="Data Entry Screen"
LAYOUT_DIALOGUES="Subscriber Dialogues"

encoded_db=$(urlencode "$DATABASE")
encoded_layout_contacts=$(urlencode "$LAYOUT_CONTACTS")
encoded_layout_dialogues=$(urlencode "$LAYOUT_DIALOGUES")

API_FIND_CONTACT="$HOST/fmi/data/v1/databases/$encoded_db/layouts/$encoded_layout_contacts/_find"
API_FIND_DIALOGUES="$HOST/fmi/data/v1/databases/$encoded_db/layouts/$encoded_layout_dialogues/_find"

# echo "--- Meeting Prep Tool: Searching for '$QUERY' ---"

# 1. Search Logic
RESULT=""

search_contact() {
    local payload="$1"
    # echo "DEBUG: Searching with payload: $payload"
    curl -s -X POST "$API_FIND_CONTACT" \
         -H "Authorization: Bearer $TOKEN" \
         -H "Content-Type: application/json" \
         -d "$payload"
}

if [[ "$QUERY" == *"@"* ]]; then
    # Email Search
    # echo "[*] Trying Exact Email Match..."
    payload=$(jq -n --arg email "==$QUERY" '{query: [{Email: $email, Active: "Active"}], limit: 1}')
    response=$(search_contact "$payload")
    
    code=$(echo "$response" | jq -r '.messages[0].code')
    
    if [ "$code" != "0" ]; then
        # echo "[*] Exact match failed. Trying Wildcard Email Match..."
        payload=$(jq -n --arg email "*$QUERY*" '{query: [{Email: $email, Active: "Active"}], limit: 1}')
        response=$(search_contact "$payload")
        code=$(echo "$response" | jq -r '.messages[0].code')
    fi
else
    # Name Search
    # Split query into First and Last
    first_name=$(echo "$QUERY" | awk '{print $1}')
    surname=$(echo "$QUERY" | awk '{$1=""; print $0}' | sed 's/^ //')
    
    if [ -z "$surname" ]; then
        echo "[!] Warning: Only one name provided. Searching First Name only (might be slow/broad)..."
        payload=$(jq -n --arg fn "$first_name" '{query: [{"First Name": $fn, "Active": "Active"}], limit: 1}')
    else
        # echo "[*] Trying Name Match: First='$first_name', Last='$surname'"
        # Construct JSON using jq carefully to handle spaces
        payload=$(jq -n --arg fn "$first_name" --arg sn "$surname" '{query: [{"First Name": $fn, "Surname": $sn, "Active": "Active"}], limit: 1}')
    fi
    response=$(search_contact "$payload")
    code=$(echo "$response" | jq -r '.messages[0].code')
fi

# 2. Handle Search Result
    
    # Auto-Refresh on 952 (Expired Token) ONLY. 
    # Code 401 in FileMaker means "No Records Found", so we should NOT refresh for that.
    if [ "$code" == "952" ]; then
        # echo "[-] Token expired (Code 952). Refreshing..." >&2
        if ./get_token.sh --silent; then
            TOKEN=$(cat ".recent_token")
            # Retry Search
            response=$(search_contact "$payload")
            code=$(echo "$response" | jq -r '.messages[0].code')
        else
            echo "[-] Error: Token refresh failed inside meeting_prep.sh"
            exit 1
        fi
    fi

    if [ "$code" == "952" ]; then
        echo "[-] Error: Token expired again after refresh."
        echo "    Please run ./get_token.sh manually."
        exit 1
    fi

    if [ "$code" != "0" ]; then
        echo "[-] Contact not in FMP (API Code: $code)"
        # Fallback/Suggestion logic could go here
        exit 0
    fi

SUB_ID=$(echo "$response" | jq -r '.response.data[0].fieldData.ID')
NAME=$(echo "$response" | jq -r '.response.data[0].fieldData["First Name"] + " " + .response.data[0].fieldData["Surname"]')
EMAIL=$(echo "$response" | jq -r '.response.data[0].fieldData.Email')
LINKEDIN=$(echo "$response" | jq -r '.response.data[0].fieldData.LinkedIn')

# Smart Company Handling
COMPANY_RAW=$(echo "$response" | jq -r '.response.data[0].fieldData["Company Station"] // .response.data[0].fieldData.Company')
if [[ "$EMAIL" == *"atnmedia.com.au"* ]]; then
    COMPANY="Australian Traffic Network (ATN)"
elif [ "$COMPANY_RAW" == "null" ] || [ -z "$COMPANY_RAW" ]; then
    COMPANY=""
else
    COMPANY="$COMPANY_RAW"
fi

# Prospector usage (last 30 days) — best-effort, never blocks the brief
USAGE_COUNT=""
USAGE_FLAG=""
if [ -n "$COMPANY" ] && [ -n "$EMAIL" ] && [ "$EMAIL" != "null" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        USAGE_BASE="http://216.250.118.221"
    else
        USAGE_BASE="http://127.0.0.1"
    fi
    USAGE_JSON=$(curl -s --max-time 15 -G "$USAGE_BASE/client-usage" --data-urlencode "company=$COMPANY" --data-urlencode "email=$EMAIL")
    if [ "$(echo "$USAGE_JSON" | jq -r '.matched // false' 2>/dev/null)" == "true" ]; then
        USAGE_COUNT=$(echo "$USAGE_JSON" | jq -r '.count')
        USAGE_FLAG=$(echo "$USAGE_JSON" | jq -r '.flag')
    fi
fi

# Extra Context Fields
CLIENT_STATUS=$(echo "$response" | jq -r '.response.data[0].fieldData["subct_SUBCO by name::Client Status"] // "Unknown"')
PRODUCT=$(echo "$response" | jq -r '.response.data[0].fieldData.Product // "Unknown"')
PROSPECT_FLAG=$(echo "$response" | jq -r '.response.data[0].fieldData.Prospect // "No"')

# echo "[+] Found Contact: $NAME | $EMAIL | $COMPANY"
# echo "    LinkedIn: $LINKEDIN"
# echo "    Status: $CLIENT_STATUS | Product: $PRODUCT | Prospect: $PROSPECT_FLAG"
# echo "    Subscriber ID: $SUB_ID"

if [ -z "$SUB_ID" ] || [ "$SUB_ID" == "null" ]; then
    echo "[-] Error: Contact found but Subscriber ID is missing."
    exit 1
fi

# 3. Fetch Dialogues
# echo "[*] Fetching Dialogues..."
payload=$(jq -n --arg id "=$SUB_ID" '{query: [{"Subscriber ID": $id}], limit: 50, sort: [{fieldName: "Contact Date", sortOrder: "descend"}]}')

response_dialogues=$(curl -s -X POST "$API_FIND_DIALOGUES" \
         -H "Authorization: Bearer $TOKEN" \
         -H "Content-Type: application/json" \
         -d "$payload")

d_code=$(echo "$response_dialogues" | jq -r '.messages[0].code')

echo ""
# 2.5 Clean up Company
if [ "$COMPANY" == "null" ] || [ -z "$COMPANY" ]; then
    DISPLAY_COMPANY=""
else
    DISPLAY_COMPANY=" ($COMPANY)"
fi

if [ "$d_code" != "0" ]; then
    INTERACTION_TEXT="No interaction history found."
    count=0
else
    count=$(echo "$response_dialogues" | jq '.response.data | length')
    INTERACTION_TEXT="Found $count recent interactions."
fi

echo "[*] Brief: $NAME ($DISPLAY_COMPANY) — $CLIENT_STATUS ($PRODUCT) — $INTERACTION_TEXT" >&2

# No-dialogue early-exit: skip the LLM call entirely and emit a banner brief.
if [ "$count" -eq 0 ]; then
    NO_DLG_JSON=$(jq -n \
        --arg company "$COMPANY" \
        --arg name "$NAME" \
        --arg status "$CLIENT_STATUS" \
        --arg product "$PRODUCT" \
        '{
            no_fmp_dialogue: true,
            subtitle: ($company + " · First Meeting"),
            meta: {lifecycle: "First Meeting", renewal_due: "—", status_label: ($status // "New")},
            snapshot: [
                {label: "Company",     value: ($company // "—")},
                {label: "Contact",     value: $name},
                {label: "Client status", value: ($status // "—")},
                {label: "Product",     value: ($product // "—")}
            ]
        }')
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    echo "$NO_DLG_JSON" | python3 "$SCRIPT_DIR/render_brief.py" \
        --name "$NAME" \
        --company "$COMPANY" \
        --interactions "0" \
        --status "$CLIENT_STATUS" \
        --meeting-intent "First Meeting" \
        --usage-count "$USAGE_COUNT" \
        --usage-flag "$USAGE_FLAG"
    exit 0
fi

    # Prepare content for both display and LLM
    FULL_CONTEXT=""
    
    # Using a temp file to handle special characters/newlines safely during the loop
    TEMP_CONTEXT_FILE="/tmp/meeting_context_$(date +%s)_$RANDOM.txt"
    > "$TEMP_CONTEXT_FILE"

    echo "$response_dialogues" | jq -c '.response.data[]' | while read -r record; do
        date=$(echo "$record" | jq -r '.fieldData["Contact Date"] // "Unknown"')
        manager=$(echo "$record" | jq -r '.fieldData["Account Manager"] // "Unknown"')
        content=$(echo "$record" | jq -r '.fieldData.Dialogue // ""')
        
        entry="--- [ $date ] by $manager ---"$'\n'"$content"$'\n\n'
        echo "$entry" >> "$TEMP_CONTEXT_FILE"
    done
    
    FULL_CONTEXT=$(cat "$TEMP_CONTEXT_FILE")
    rm -f "$TEMP_CONTEXT_FILE"

    if [ -n "$OPENAI_KEY" ]; then
        echo "[*] Generating brief via OpenAI..." >&2


        # Load Knowledge Base
        # Use relative path since we are in the same dir
        KNOWLEDGE_BASE_FILE="./knowledge_base.txt"
        
        KNOWLEDGE_BASE_CONTENT=""
        if [ -f "$KNOWLEDGE_BASE_FILE" ]; then
             # echo "[*] Loaded Knowledge Base."
             KNOWLEDGE_BASE_CONTENT=$(cat "$KNOWLEDGE_BASE_FILE")
        else
             echo "[!] Warning: Knowledge Base file not found at $KNOWLEDGE_BASE_FILE"
        fi

        # Determine Context Type for prompt
        CONTEXT_TYPE="General"
        
        # 1. Base Context from FileMaker Data
        if [ "$PROSPECT_FLAG" == "Yes" ] || [ "$CLIENT_STATUS" == "Potential" ]; then
            CONTEXT_TYPE="Prospect/New Business"
        elif [ "$CLIENT_STATUS" == "Existing" ]; then
            CONTEXT_TYPE="Existing Client"
        elif [ "$CLIENT_STATUS" == "Lapsed" ]; then
             CONTEXT_TYPE="Lapsed Client"
        fi

        # 2. Override/Refine based on Calendar Color (User Intent)
        MEETING_INTENT=""
        if [ "$COLOR_ID" == "11" ]; then # Tomato
             MEETING_INTENT="Existing Client / Renewal Check-in"
             CONTEXT_INSTRUCTION="Focus on relationship health, upsell opportunities, and renewal status. Check for any unresolved support issues."
        elif [ "$COLOR_ID" == "3" ]; then # Grape
             MEETING_INTENT="Key Contact Meeting"
             CONTEXT_INSTRUCTION="This is a key relationship meeting with a strategically important contact. Focus on stakeholder dynamics, what this contact cares about commercially, and how to deepen the relationship and unlock new opportunities."
        elif [ "$COLOR_ID" == "2" ]; then # Sage
             MEETING_INTENT="Onboarding / Training"
             CONTEXT_INSTRUCTION="Focus on user adoption. Provide a training checklist (Login, Search, Alerts). Ensure they know how to use the platform effectively."
        else
             MEETING_INTENT="General Meeting"
             CONTEXT_INSTRUCTION="Provide a balanced summary."
        fi

        # Construct the prompt
        SYSTEM_PROMPT=$(cat <<EOF
You are preparing a commercial meeting brief for an Account Director at 'Prospector', a B2B intent intelligence platform.

Be commercial, not academic. Avoid generic statements. Focus on how the company makes money, wins clients, sells to brands or agencies, and where Prospector can help create commercial advantage. Think like a sales leader, not a marketer.

=== KNOWLEDGE BASE START ===
$KNOWLEDGE_BASE_CONTENT
=== KNOWLEDGE BASE END ===

CONTEXT FOR THIS MEETING:
- Contact: $NAME from $COMPANY
- Relationship Status (CRM): $CONTEXT_TYPE
- Meeting Type (Calendar signal): $MEETING_INTENT
- Product: $PRODUCT
- Calendar context note: $CONTEXT_INSTRUCTION

CORE RULES:
- Use only the CRM dialogue you are given. Do not guess.
- If something is not in the CRM dialogue, set the value to "Not found in CRM".
- Be direct and specific. No padding. No generic SaaS language.
- Do not overstate certainty. Label inferences as inferences.
- Plain text only in field values — no HTML, no markdown, no asterisks, no bullet characters.

SECTION-SPECIFIC RULES:
- Prospect Focus: extract what kinds of prospects this contact is hunting for — industries/verticals, whether they sell direct or via agencies, which states/regions matter. Quote dialogue where useful.
- Blockers: surface ONLY explicit complaints or barriers found in the dialogue (e.g. "flagged Coles contacts as out of date", "said he has no time to log in"). Do NOT infer dissatisfaction from neutral language. If none are logged, set the value to "None raised".
- Last Meeting Next Steps: find the most recent dialogue entry that names agreed actions (look for phrases like "to send", "to circulate", "will follow up", "next step"). For each step, look at SUBSEQUENT dialogue entries for evidence the step was actioned. Status must be exactly one of: "Done", "Partially done", "Not done", "Unclear". If no explicit next steps were logged in the last interaction, set "had_steps": false and leave "steps": [].
- Practical Meeting Moves: bias the moves to the next-step status. If a step is "Not done", at least one move should open the conversation about why it did not happen. If "Done", build on it (push for next stage). If "Partially done", ask about the remaining piece. Always at least three moves.

OUTPUT FORMAT (strict):
Return a single JSON object that exactly matches this schema. No preamble, no closing remarks, no code fences — just the JSON object.

{
  "subtitle": "<Company> · <Meeting type label>",
  "meta": {
    "lifecycle": "<e.g. Active · Renewal | Lapsed · Reactivation | Active · Expansion | Onboarding>",
    "renewal_due": "<e.g. Nov 2026 — extract from dialogue, or '—' if unknown>",
    "status_label": "<e.g. Active Connector | Lapsed | Onboarding | Renewal Pending>"
  },
  "snapshot": [
    {"label": "Company",          "value": "..."},
    {"label": "Contact",          "value": "..."},
    {"label": "Meeting type",     "value": "..."},
    {"label": "Lifecycle stage",  "value": "..."},
    {"label": "Relationship",     "value": "..."},
    {"label": "Main risk",        "value": "..."},
    {"label": "Main opportunity", "value": "..."}
  ],
  "prospect_focus": [
    {"label": "Industries & verticals", "value": "..."},
    {"label": "Agency vs Direct",       "value": "..."},
    {"label": "Region / state focus",   "value": "..."}
  ],
  "blockers": [
    {"label": "Data accuracy / freshness", "value": "..."},
    {"label": "Time / proactive use",      "value": "..."},
    {"label": "Other blockers",            "value": "..."}
  ],
  "last_meeting_next_steps": {
    "had_steps": true,
    "steps": [
      {
        "step":     "<the agreed action, as logged>",
        "status":   "Done|Partially done|Not done|Unclear",
        "evidence": "<the dialogue line(s) that support this status — quote dates where possible>"
      }
    ]
  },
  "meeting_moves": [
    {
      "title": "<short, action-oriented imperative>",
      "rows": [
        {"label": "Evidence", "value": "..."},
        {"label": "Question", "value": "..."},
        {"label": "Example",  "value": "..."},
        {"label": "Objection","value": "..."},
        {"label": "Response", "value": "..."}
      ]
    }
  ]
}

Provide at least three meeting_moves. Return only the JSON.
EOF
)

        USER_PROMPT=$(cat <<EOF
Here is the dialogue history from CRM (most recent first):

$FULL_CONTEXT

----------------

Contact Details:
Name: $NAME
Company: $COMPANY
LinkedIn: $LINKEDIN
Client Status: $CLIENT_STATUS
Product: $PRODUCT
Prospect Flag: $PROSPECT_FLAG

Return the JSON object now. Use only what is in the CRM dialogue above. Anything not present should be "Not found in CRM".
EOF
)

        MODEL_ID="gpt-4o"
        API_URL="https://api.openai.com/v1/chat/completions"
        AUTH_HEADER="Authorization: Bearer $OPENAI_KEY"

        # Create JSON payload safely with jq — request strict JSON output
        JSON_PAYLOAD=$(jq -n \
                  --arg system "$SYSTEM_PROMPT" \
                  --arg user "$USER_PROMPT" \
                  --arg model "$MODEL_ID" \
                  '{
                    model: $model,
                    messages: [
                      {role: "system", content: $system},
                      {role: "user", content: $user}
                    ],
                    response_format: {type: "json_object"}
                  }')

        if [ -z "$JSON_PAYLOAD" ]; then
             echo "[-] Error: JSON Payload for OpenAI is empty. JQ failed?" >&2
        fi

        SUMMARY_RESPONSE=$(curl -s -X POST "$API_URL" \
             -H "Content-Type: application/json" \
             -H "$AUTH_HEADER" \
             -d "$JSON_PAYLOAD")

        CURL_RET=$?
        if [ $CURL_RET -ne 0 ]; then
             echo "[-] Curl failed with exit code $CURL_RET" >&2
        fi

        # Extract JSON content from the AI response
        AI_JSON=$(echo "$SUMMARY_RESPONSE" | jq -r '.choices[0].message.content')

        if [ "$AI_JSON" == "null" ] || [ -z "$AI_JSON" ]; then
             echo "[-] Error getting brief from OpenAI:" >&2
             echo "$SUMMARY_RESPONSE" >&2
             # Emit a minimal error block so the email still sends
             echo "<table role=\"presentation\" width=\"640\" style=\"background:#fff; padding:24px; border-radius:8px; border:1px solid #eef0f3;\"><tr><td><div style=\"font-family:'Inter',sans-serif; font-size:14px; color:#c93838; font-weight:600;\">Brief generation failed — OpenAI returned no content for $NAME.</div></td></tr></table>"
        else
             # Pipe JSON through Python renderer to produce email-safe HTML
             SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
             echo "$AI_JSON" | python3 "$SCRIPT_DIR/render_brief.py" \
                  --name "$NAME" \
                  --company "$COMPANY" \
                  --interactions "$count recent" \
                  --status "$CLIENT_STATUS" \
                  --meeting-intent "$MEETING_INTENT" \
                  --usage-count "$USAGE_COUNT" \
                  --usage-flag "$USAGE_FLAG"
        fi

    else
        # No key, just print raw
        echo "$FULL_CONTEXT"
        echo "============================================================"
        echo "Use the text above this line as context for your LLM summarization."
    fi
