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
else
    count=$(echo "$response_dialogues" | jq '.response.data | length')
    INTERACTION_TEXT="Found $count recent interactions."
fi

echo "<p><strong>MEETING PREPARATION BRIEF: $NAME</strong></p>"
echo "<p>Subject: $NAME$DISPLAY_COMPANY</p>"
echo "<p>LinkedIn: $LINKEDIN</p>"
echo "<p>Context: $CLIENT_STATUS ($PRODUCT) $INTERACTION_TEXT</p>"
echo ""

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
        echo "Generating Smart Summary (powered by OpenAI)..."
        echo "(This might take a few seconds)"
        echo ""
        
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
        SYSTEM_PROMPT="You are preparing a commercial meeting brief for an Account Director at 'Prospector', a B2B intent intelligence platform.

Do NOT write a generic CRM summary. Write something useful for a sales meeting.

Be commercial, not academic. Avoid generic statements. Focus on how the company makes money, wins clients, sells to brands or agencies, and where Prospector can help create commercial advantage. Think like a sales leader, not a marketer.

The final output should feel like something the Account Director can actually use in a meeting tomorrow.

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
- If something is not available in the CRM dialogue, write 'not found in CRM'.
- Be direct and specific. No padding. No generic SaaS language. No academic summaries.
- Do not overstate certainty. If something is inferred from limited evidence, label it as an inference.
- Prioritise practical usefulness over completeness.

OUTPUT FORMAT (strict):
- Use HTML only. No markdown.
- Use <h3> for each numbered section heading.
- Use <p> for paragraphs, <ul>/<li> for lists, <strong> for emphasis.
- Do NOT use <h1> or <h2> (those are reserved for the email shell).
- Begin the response immediately with section 1 — no preamble, no greeting."

        USER_PROMPT="Here is the dialogue history from CRM:\n\n$FULL_CONTEXT\n\n----------------\n\nContact Details:\nName: $NAME\nCompany: $COMPANY\nLinkedIn: $LINKEDIN\nClient Status: $CLIENT_STATUS\nProduct: $PRODUCT\nProspect Flag: $PROSPECT_FLAG\n\nProduce the brief using exactly these 12 sections in this order:\n\n1. Meeting snapshot — Company; Contact; Meeting type; Account lifecycle stage; Current relationship status; Main commercial risk; Main commercial opportunity.\n\n2. Commercial read — A short, blunt interpretation of what this meeting is really about commercially. Explain why it is happening, what the person probably cares about commercially, how the company makes money or wins clients, where Prospector may or may not fit, and what risk/blocker/objection needs to be confronted. AVOID vague statements like 'they need relevant insights', 'timing is important' or 'ask about their priorities'.\n\n3. Account lifecycle — Current status (former / active / renewal / reactivation / expansion / switch-off risk); how long they have used Prospector if known; why they originally bought if known; why they renewed, paused, churned or switched off; what stage this meeting represents; any important renewal/cancellation/reactivation context.\n\n4. Stakeholder map — Separate people by commercial role, not just name. Cover: Main contact; Decision-maker; Economic buyer; Daily users; Champion; Blocker / sceptic; Missing stakeholders; Other internal names mentioned in CRM; What each person appears to care about. If a role is unclear, say 'not found in CRM'.\n\n5. Brand and vertical appetite — Types of brands they usually care about; specific brands mentioned; verticals they sell into; target categories; trigger types that matter to them; whether they care about enterprise, challenger, retail, FMCG, sport, agencies, not-for-profits or other categories; signs of brands they are trying to win, retain or grow. Turn vague statements into commercial detail.\n\n6. Agency / buying-path intelligence — Do they sell direct to brands, via agencies, or both? Do they work with an agency patch? Which agencies are mentioned? Are the agencies HoldCo / network, independents, direct advertisers or unknown? Are they focused on Tier 1 agencies, independents, direct advertisers or a mix? Are they chasing new business, existing clients or expansion within known relationships? Does the buying path change how Prospector should be positioned? If agency type is not clear, say 'not found in CRM'.\n\n7. Region or patch focus — Geographic focus; state / city / national patch; agency patch; brand category patch; new business patch; existing client patch; any territory ownership mentioned in CRM. If not found, say 'not found in CRM'.\n\n8. Prospector value evidence — Classify the evidence, do not just summarise it. Cover: Evidence of value; evidence of poor adoption; features that worked; features that did not land; specific use cases mentioned; specific wins or near-wins; what the account previously cared about; what appears to have blocked value; whether the issue appears to be relevance, workflow, adoption, budget, timing, stakeholder buy-in or unclear commercial outcomes.\n\n9. Recommended meeting angle — How to open the meeting; the main commercial point to make; what issue to confront directly; what NOT to overclaim; what to show; what outcome to push for; how to position Prospector for THIS specific account.\n\n10. Proof points to bring — Specific brand examples to mention; specific agency examples to mention; relevant trigger examples; suggested searches to run live; suggested alerts to recommend; similar client use cases if available; any evidence from CRM that supports the examples. If no specific examples are available, say 'not found in CRM' and suggest the type of example that would be useful.\n\n11. Practical meeting moves — Do NOT only provide questions. Provide practical meeting moves. Each meeting move must include: Commercial point to make; Evidence from CRM; Question to ask; Example to show (if available); Likely objection; Recommended response. Provide at least three meeting moves.\n\n12. Suggested questions — Every question must be specific to the account and meeting. NO generic questions. For each question, include: Question; Why ask this; What to listen for; Possible follow-up. Provide at least four questions.\n\nReminder: if the CRM dialogue does not contain the information for a sub-bullet, write 'not found in CRM' rather than guessing. Begin with section 1 immediately, no preamble."

        MODEL_ID="gpt-4o"
        API_URL="https://api.openai.com/v1/chat/completions"
        AUTH_HEADER="Authorization: Bearer $OPENAI_KEY"

        # Create JSON payload safely with jq
        JSON_PAYLOAD=$(jq -n \
                  --arg system "$SYSTEM_PROMPT" \
                  --arg user "$USER_PROMPT" \
                  --arg model "$MODEL_ID" \
                  '{
                    model: $model,
                    messages: [
                      {role: "system", content: $system},
                      {role: "user", content: $user}
                    ]
                  }')
                  
        if [ -z "$JSON_PAYLOAD" ]; then
             echo "[-] Error: JSON Payload for OpenAI is empty. JQ failed?" >&2
             echo "User Prompt length: ${#USER_PROMPT}" >&2
        fi

        SUMMARY_RESPONSE=$(curl -s -X POST "$API_URL" \
             -H "Content-Type: application/json" \
             -H "$AUTH_HEADER" \
             -H "HTTP-Referer: https://github.com/alexsheath" \
             -d "$JSON_PAYLOAD")
             
        CURL_RET=$?
        if [ $CURL_RET -ne 0 ]; then
             echo "[-] Curl failed with exit code $CURL_RET" >&2
        fi

        # Extract content
        SUMMARY_TEXT=$(echo "$SUMMARY_RESPONSE" | jq -r '.choices[0].message.content')
        
        if [ "$SUMMARY_TEXT" == "null" ] || [ -z "$SUMMARY_TEXT" ]; then
             echo "[-] Error getting summary from OpenAI:" >&2
             echo "$SUMMARY_RESPONSE" >&2
             echo "" >&2
             echo "Falling back to raw log:"
             echo ""
             echo "Falling back to raw log:"
             echo "$FULL_CONTEXT"
        else
             echo -e "$SUMMARY_TEXT"
        fi

    else
        # No key, just print raw
        echo "$FULL_CONTEXT"
        echo "============================================================"
        echo "Use the text above this line as context for your LLM summarization."
    fi
