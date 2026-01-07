#!/bin/bash

# Configuration
HOST="https://fms14.filemakerstudio.com.au"
DATABASE="IRD Subscribing Contacts"
DEFAULT_TOKEN="dcc790a415765bc93c3d1d2a5060a00438e554c6f6cef153754b"

QUERY="$1"
TOKEN="${2:-$DEFAULT_TOKEN}"
OPENAI_KEY="$3"
COLOR_ID="$4"
OPENROUTER_KEY=$(cat ../.openrouter_key 2>/dev/null || cat .openrouter_key 2>/dev/null)

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
    
    if [ "$code" == "952" ]; then
        echo "[-] Error: Invalid or Expired Token (Code 952)."
        echo "    Please run with a valid token: ./meeting_prep.sh \"$QUERY\" \"NEW_TOKEN\""
        exit 1
    fi

    if [ "$code" != "0" ]; then
        echo "[-] Contact NOT FOUND. (API Code: $code)"
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
    TEMP_CONTEXT_FILE="/tmp/meeting_context.txt"
    > "$TEMP_CONTEXT_FILE"

    echo "$response_dialogues" | jq -c '.response.data[]' | while read -r record; do
        date=$(echo "$record" | jq -r '.fieldData["Contact Date"] // "Unknown"')
        manager=$(echo "$record" | jq -r '.fieldData["Account Manager"] // "Unknown"')
        content=$(echo "$record" | jq -r '.fieldData.Dialogue // ""')
        
        entry="--- [ $date ] by $manager ---"$'\n'"$content"$'\n\n'
        echo "$entry" >> "$TEMP_CONTEXT_FILE"
    done
    
    FULL_CONTEXT=$(cat "$TEMP_CONTEXT_FILE")

    # 4. LinkedIn Enrichment (Apify) - Profile Posts Scraper
    APIFY_KEY_FILE=".apify_key"
    APIFY_CONTEXT=""
    
    if [ -f "$APIFY_KEY_FILE" ] && [ -n "$LINKEDIN" ]; then
        APIFY_TOKEN=$(cat "$APIFY_KEY_FILE")
        if [ -n "$APIFY_TOKEN" ]; then
            # echo "Processing LinkedIn Profile via Apify..."
            # echo "(Fetching recent posts using Actor: LQQIXN9Othf8f7R5n)"
            
            # Input: { "urls": [ "..." ], "minDelay": 2, "maxDelay": 5 }
            APIFY_INPUT=$(jq -n --arg url "$LINKEDIN" '{urls: [$url], minDelay: 2, maxDelay: 5}')
            
            # Actor: LQQIXN9Othf8f7R5n (Linkedin profile post scraper)
            APIFY_URL="https://api.apify.com/v2/acts/LQQIXN9Othf8f7R5n/run-sync-get-dataset-items?token=$APIFY_TOKEN"
            
            APIFY_RESPONSE=$(curl -s -X POST "$APIFY_URL" \
                 -H "Content-Type: application/json" \
                 -d "$APIFY_INPUT")
                 
            # Response is an Array of Objects (Posts)
            # We want to extract:
            # 1. Headline (from the author object of the first post)
            # 2. Recent Posts (Text and Date)
            
            # Check if we got an array
            IS_ARRAY=$(echo "$APIFY_RESPONSE" | jq -r 'type')
            
            if [ "$IS_ARRAY" == "array" ]; then
                # Extract Headline
                L_HEADLINE=$(echo "$APIFY_RESPONSE" | jq -r '.[0].author.headline // empty')
                
                # Extract Top 3 Posts
                # Format: "On [Date]: [First 200 chars]..."
                L_POSTS=$(echo "$APIFY_RESPONSE" | jq -r '.[0:3] | .[] | "On " + (.posted_at.date // "Unknown") + ": " + (.text[0:200] // "") + "..."')
                
                if [ -n "$L_HEADLINE" ] || [ -n "$L_POSTS" ]; then
                    # echo "[+] LinkedIn Data Fetched successfully."
                    APIFY_CONTEXT=$'\n'"--- LINKEDIN INTELLIGENCE ---"$'\n'
                    APIFY_CONTEXT+="Headline (Current Role): $L_HEADLINE"$'\n'
                    APIFY_CONTEXT+="Recent Posts / Activity:"$'\n'"$L_POSTS"$'\n'
                    
                    # Append to Full Context
                    FULL_CONTEXT+="$APIFY_CONTEXT"
                else
                    echo "[-] Apify returned data but no posts/headline found."
                fi
            else 
                echo "[-] Apify Error or No Data:"
                echo "$APIFY_RESPONSE" | jq -r '.error.message // "Unknown Error"'
            fi
        fi
    fi

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
             MEETING_INTENT="New Business Pitch"
             CONTEXT_INSTRUCTION="Focus on value proposition, competitive advantages, and closing the deal. Identify pain points that Prospector solves."
        elif [ "$COLOR_ID" == "2" ]; then # Sage
             MEETING_INTENT="Onboarding / Training"
             CONTEXT_INSTRUCTION="Focus on user adoption. Provide a training checklist (Login, Search, Alerts). Ensure they know how to use the platform effectively."
        else
             MEETING_INTENT="General Meeting"
             CONTEXT_INSTRUCTION="Provide a balanced summary."
        fi

        # Construct the prompt
        SYSTEM_PROMPT="You are an expert executive assistant for 'Prospector', a B2B intent intelligence platform.

Here is the Knowledge Base about Prospector and its client types. Use this to deeply understand the business context, value proposition, and the specific needs of different client types:

=== KNOWLEDGE BASE START ===
$KNOWLEDGE_BASE_CONTENT
=== KNOWLEDGE BASE END ===

You will be given a history of dialogue notes for a contact ($NAME from $COMPANY).
Relationship Status (CRM): $CONTEXT_TYPE
Meeting Type (Calendar): $MEETING_INTENT
Product: $PRODUCT

Your goal is to prepare a briefing for an upcoming meeting.
Use the Knowledge Base to provide specific, strategic advice based on the Client Group and Relationship Status.
IMPORTANT INSTRUCTION: $CONTEXT_INSTRUCTION
Do NOT just summarize the notes; interpret them through the lens of the Knowledge Base and the specific Meeting Type."

        USER_PROMPT="Here is the dialogue history:\n\n$FULL_CONTEXT\n\n----------------\n\nContact Details:\nName: $NAME\nCompany: $COMPANY\nLinkedIn: $LINKEDIN\nClient Status: $CLIENT_STATUS\nProduct: $PRODUCT\nProspect Flag: $PROSPECT_FLAG\n\nPlease provide a summary that includes:\n1. A quick summary of the relationship status (Context: $CONTEXT_TYPE).\n2. Key topics discussed in the past.\n3. Important context (blockers, wins, personal details).\n4. Suggested key questions to ask in the next meeting, specifically tailored to their client type and status (refer to Knowledge Base).\n\nKeep it professional and concise.\nIMPORTANT: Format your response using HTML tags. Use <p> for paragraphs. Use <ul>/<ol> and <li> for lists. Use <strong> for bold. Do NOT use markdown."

        # Create JSON payload safely with jq
        JSON_PAYLOAD=$(jq -n \
                  --arg system "$SYSTEM_PROMPT" \
                  --arg user "$USER_PROMPT" \
                  '{
                    model: "openai/gpt-4o",
                    messages: [
                      {role: "system", content: $system},
                      {role: "user", content: $user}
                    ]
                  }')

        # Call OpenRouter API (Fallback to OpenAI if key missing)
        if [ -n "$OPENROUTER_KEY" ]; then
            API_URL="https://openrouter.ai/api/v1/chat/completions"
            AUTH_HEADER="Authorization: Bearer $OPENROUTER_KEY"
        else
            API_URL="https://api.openai.com/v1/chat/completions"
            AUTH_HEADER="Authorization: Bearer $OPENAI_KEY"
        fi

        SUMMARY_RESPONSE=$(curl -s -X POST "$API_URL" \
             -H "Content-Type: application/json" \
             -H "$AUTH_HEADER" \
             -H "HTTP-Referer: https://github.com/alexsheath" \
             -d "$JSON_PAYLOAD")

        # Extract content
        SUMMARY_TEXT=$(echo "$SUMMARY_RESPONSE" | jq -r '.choices[0].message.content')
        
        if [ "$SUMMARY_TEXT" == "null" ]; then
             echo "[-] Error getting summary from OpenAI:"
             echo "$SUMMARY_RESPONSE"
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
