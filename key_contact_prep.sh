#!/bin/bash

# Configuration
cd "$(dirname "$0")" || exit 1

HOST="https://fms14.filemakerstudio.com.au"
DATABASE="IRD Subscribing Contacts"
TOKEN_FILE=".recent_token"
OPENAI_KEY_FILE=".openai_key"
OPENROUTER_KEY_FILE="../.openrouter_key"
LOGO_FILE="logo.png"

# Arguments
QUERY="$1"
if [ -z "$QUERY" ]; then
    echo "Usage: ./key_contact_prep.sh \"Name or Email\""
    exit 1
fi

# 1. Keys & Tokens
if [ -f "$TOKEN_FILE" ]; then TOKEN=$(cat "$TOKEN_FILE"); else ./get_token.sh; TOKEN=$(cat "$TOKEN_FILE"); fi
OPENAI_KEY=$(cat "$OPENAI_KEY_FILE" 2>/dev/null)
OPENROUTER_KEY=$(cat "$OPENROUTER_KEY_FILE" 2>/dev/null || cat ".openrouter_key" 2>/dev/null)

# 2. FileMaker Search
encoded_db=$(echo "$DATABASE" | jq -Rr @uri)
API_FIND_CONTACT="$HOST/fmi/data/v1/databases/$encoded_db/layouts/Data%20Entry%20Screen/_find"
API_FIND_DIALOGUES="$HOST/fmi/data/v1/databases/$encoded_db/layouts/Subscriber%20Dialogues/_find"

echo "[*] Searching for '$QUERY'..."
if [[ "$QUERY" == *"@"* ]]; then
    payload=$(jq -n --arg email "==$QUERY" '{query: [{Email: $email, Active: "Active"}], limit: 1}')
else
    first_name=$(echo "$QUERY" | awk '{print $1}')
    surname=$(echo "$QUERY" | awk '{$1=""; print $0}' | sed 's/^ //')
    if [ -z "$surname" ]; then
        payload=$(jq -n --arg fn "$first_name" '{query: [{"First Name": $fn, "Active": "Active"}], limit: 1}')
    else
        payload=$(jq -n --arg fn "$first_name" --arg sn "$surname" '{query: [{"First Name": $fn, "Surname": $sn, "Active": "Active"}], limit: 1}')
    fi
fi

response=$(curl -s -X POST "$API_FIND_CONTACT" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$payload")
code=$(echo "$response" | jq -r '.messages[0].code')

if [ "$code" != "0" ]; then echo "[-] Contact not found (Code: $code)"; exit 1; fi

SUB_ID=$(echo "$response" | jq -r '.response.data[0].fieldData.ID')
NAME=$(echo "$response" | jq -r '.response.data[0].fieldData["First Name"] + " " + .response.data[0].fieldData["Surname"]')
EMAIL=$(echo "$response" | jq -r '.response.data[0].fieldData.Email')
LINKEDIN=$(echo "$response" | jq -r '.response.data[0].fieldData.LinkedIn')
CLIENT_STATUS=$(echo "$response" | jq -r '.response.data[0].fieldData["subct_SUBCO by name::Client Status"] // "Unknown"')
PRODUCT=$(echo "$response" | jq -r '.response.data[0].fieldData.Product // "Unknown"')
PROSPECT_FLAG=$(echo "$response" | jq -r '.response.data[0].fieldData.Prospect // "No"')

# Smart Company Handling
COMPANY_RAW=$(echo "$response" | jq -r '.response.data[0].fieldData["Company Station"] // .response.data[0].fieldData.Company')

if [[ "$EMAIL" == *"atnmedia.com.au"* ]]; then
    COMPANY="Australian Traffic Network (ATN)"
elif [ "$COMPANY_RAW" == "null" ] || [ -z "$COMPANY_RAW" ]; then
    COMPANY="Unknown"
else
    COMPANY="$COMPANY_RAW"
fi

# 3. Dialogues
echo "[*] Fetching interaction history..."
payload=$(jq -n --arg id "=$SUB_ID" '{query: [{"Subscriber ID": $id}], limit: 50, sort: [{fieldName: "Contact Date", sortOrder: "descend"}]}')
response_dialogues=$(curl -s -X POST "$API_FIND_DIALOGUES" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$payload")
count=$(echo "$response_dialogues" | jq '.response.data | length')

DIALOGUE_LOG=$(echo "$response_dialogues" | jq -r '.response.data[] | "On " + .fieldData["Contact Date"] + " by " + .fieldData["Account Manager"] + ":\n" + .fieldData.Dialogue + "\n"')

# 4. LinkedIn (Optional / If available)
LINKEDIN_BRIEF=""
if [ -n "$LINKEDIN" ]; then
    echo "[*] Found LinkedIn: $LINKEDIN"
    # Placeholder for LinkedIn enrichment if we want to add it here too
fi

# 5. OpenAI Strategic Call
echo "[*] Generating Strategic Briefing..."
KNOWLEDGE_BASE=$(cat "knowledge_base.txt" 2>/dev/null)

SYSTEM_PROMPT="You are a high-level strategic advisor for Mick Sheath at 'Prospector'. 
Your task is to analyze a contact's history and provide a high-impact meeting preparation report.

Knowledge Base:
$KNOWLEDGE_BASE

Structure your response as JSON with these keys:
- objective: A one-sentence primary objective for the meeting.
- blocker: The biggest likely blocker or concern.
- angle: The best strategic approach/angle for the conversation.
- questions: A list of 5 powerful, open-ended questions.
- summary: A professional 3-4 paragraph briefing summary.

Contact: $NAME from $COMPANY
Relationship: $CLIENT_STATUS ($PRODUCT)
Interaction Log:
$DIALOGUE_LOG"

if [ -n "$OPENROUTER_KEY" ]; then
    API_URL="https://openrouter.ai/api/v1/chat/completions"
    AUTH="Authorization: Bearer $OPENROUTER_KEY"
    MODEL="openai/gpt-4o"
else
    API_URL="https://api.openai.com/v1/chat/completions"
    AUTH="Authorization: Bearer $OPENAI_KEY"
    MODEL="gpt-4o"
fi

JSON_INPUT=$(jq -n --arg sys "$SYSTEM_PROMPT" --arg model "$MODEL" '{model: $model, messages: [{role: "system", content: $sys}], response_format: {type: "json_object"}}')
AI_RESPONSE=$(curl -s -X POST "$API_URL" -H "Content-Type: application/json" -H "$AUTH" -d "$JSON_INPUT")
AI_JSON=$(echo "$AI_RESPONSE" | jq -r '.choices[0].message.content')

# 6. Generate Pretty HTML
FILENAME="Key_Contact_${NAME// /_}_$(date +%s).html"
LOGO_B64=$(base64 -i "$LOGO_FILE" | tr -d '\n')

# Extract fields from AI JSON
OBJ=$(echo "$AI_JSON" | jq -r '.objective')
BLOCK=$(echo "$AI_JSON" | jq -r '.blocker')
ANGLE=$(echo "$AI_JSON" | jq -r '.angle')
SUMMARY=$(echo "$AI_JSON" | jq -r '.summary')
QUESTIONS_HTML=$(echo "$AI_JSON" | jq -r '.questions | map("<li>"+.+"</li>") | join("\n")')

cat <<EOF > "$FILENAME"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Strategic Prep: $NAME</title>
    <style>
        :root { --bg: #f6f7f9; --card: #ffffff; --text: #111827; --muted: #6b7280; --border: #e5e7eb; --accent: #1f6feb; --shadow: 0 10px 24px rgba(16,24,40,.10); --radius: 16px; }
        body { margin: 0; background: var(--bg); color: var(--text); font-family: system-ui, sans-serif; line-height: 1.6; }
        .wrap { max-width: 980px; margin: 0 auto; padding: 40px 20px; }
        .header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 24px; }
        .logo { max-height: 60px; }
        .title { font-size: 32px; letter-spacing: -0.02em; margin: 0; }
        .chips { display: flex; gap: 8px; margin-top: 12px; }
        .chip { padding: 6px 12px; border-radius: 999px; border: 1px solid var(--border); background: #fff; font-size: 13px; color: var(--muted); }
        .grid { display: grid; grid-template-columns: 1fr; gap: 20px; margin-top: 20px; }
        @media (min-width: 900px) { .grid { grid-template-columns: 1.2fr 0.8fr; } }
        .card { background: var(--card); border: 1px solid var(--border); border-radius: var(--radius); box-shadow: var(--shadow); padding: 24px; }
        .card h2 { font-size: 14px; text-transform: uppercase; letter-spacing: 0.05em; color: var(--muted); margin: 0 0 16px; }
        .priority { border: 1px solid var(--border); border-radius: 12px; padding: 16px; background: #fbfdff; margin-bottom: 12px; }
        .priority .label { font-size: 11px; text-transform: uppercase; color: var(--muted); margin-bottom: 4px; }
        .priority .value { margin: 0; font-weight: 700; font-size: 17px; }
        .bullets { margin: 0; padding-left: 20px; }
        .bullets li { margin-bottom: 12px; }
        .md-summary { white-space: pre-wrap; font-size: 15px; }
        .footer { margin-top: 40px; text-align: center; font-size: 12px; color: var(--muted); }
    </style>
</head>
<body>
    <div class="wrap">
        <div class="header">
            <div>
                <h1 class="title">Strategic Prep: $NAME</h1>
                <div class="chips">
                    <span class="chip"><strong>Status:</strong> $CLIENT_STATUS</span>
                    <span class="chip"><strong>Product:</strong> $PRODUCT</span>
                    <span class="chip"><strong>Company:</strong> $COMPANY</span>
                </div>
            </div>
            <img src="data:image/png;base64,$LOGO_B64" class="logo">
        </div>

        <div class="grid">
            <div class="card">
                <h2>90-Second Strategic Scan</h2>
                <div class="priority">
                    <div class="label">Primary Objective</div>
                    <p class="value">$OBJ</p>
                </div>
                <div class="priority">
                    <div class="label">Biggest Blocker</div>
                    <p class="value">$BLOCK</p>
                </div>
                <div class="priority">
                    <div class="label">Best Angle</div>
                    <p class="value">$ANGLE</p>
                </div>
            </div>
            <div class="card">
                <h2>Suggested Questions</h2>
                <ul class="bullets">
                    $QUESTIONS_HTML
                </ul>
            </div>
        </div>

        <div class="card" style="margin-top: 20px;">
            <h2>Full Briefing Summary</h2>
            <div class="md-summary">$SUMMARY</div>
        </div>

        <div class="footer">Generated by Key Contact Prep Tool • $(date)</div>
    </div>
</body>
</html>
EOF

echo "[*] Success: $FILENAME"
open "$FILENAME"
