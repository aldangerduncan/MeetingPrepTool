#!/bin/bash
# pull_dialogue.sh — pulls RAW interaction history for a contact from FileMaker
# and writes it to dialogue_latest.json (full data) + dialogue_latest.txt (readable).
# No OpenAI, no HTML. Designed to be read back by the meeting-prep workflow.
#
# Usage: ./pull_dialogue.sh "Name or Email"

cd "$(dirname "$0")" || exit 1

HOST="https://fms14.filemakerstudio.com.au"
DATABASE="IRD Subscribing Contacts"
TOKEN_FILE=".recent_token"
OUT_JSON="dialogue_latest.json"
OUT_TXT="dialogue_latest.txt"

QUERY="$1"
if [ -z "$QUERY" ]; then
    echo "Usage: ./pull_dialogue.sh \"Name or Email\""
    exit 1
fi

# 1. Token
if [ -f "$TOKEN_FILE" ]; then TOKEN=$(cat "$TOKEN_FILE"); else ./get_token.sh --silent; TOKEN=$(cat "$TOKEN_FILE"); fi

encoded_db=$(echo "$DATABASE" | jq -Rr @uri)
API_FIND_CONTACT="$HOST/fmi/data/v1/databases/$encoded_db/layouts/Data%20Entry%20Screen/_find"
API_FIND_DIALOGUES="$HOST/fmi/data/v1/databases/$encoded_db/layouts/Subscriber%20Dialogues/_find"

# 2. Find contact (by email or first/last name)
echo "[*] Searching for '$QUERY'..."
if [[ "$QUERY" == *"@"* ]]; then
    payload=$(jq -n --arg email "==$QUERY" '{query: [{Email: $email}], limit: 1}')
else
    first_name=$(echo "$QUERY" | awk '{print $1}')
    surname=$(echo "$QUERY" | awk '{$1=""; print $0}' | sed 's/^ //')
    if [ -z "$surname" ]; then
        payload=$(jq -n --arg fn "$first_name" '{query: [{"First Name": $fn}], limit: 1}')
    else
        payload=$(jq -n --arg fn "$first_name" --arg sn "$surname" '{query: [{"First Name": $fn, "Surname": $sn}], limit: 1}')
    fi
fi

response=$(curl -s -X POST "$API_FIND_CONTACT" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$payload")
code=$(echo "$response" | jq -r '.messages[0].code')

# Refresh token on expiry (952) and retry
if [ "$code" == "952" ] || [ "$code" == "951" ]; then
    echo "[!] Token expired. Refreshing..."
    ./get_token.sh --silent
    TOKEN=$(cat "$TOKEN_FILE")
    response=$(curl -s -X POST "$API_FIND_CONTACT" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$payload")
    code=$(echo "$response" | jq -r '.messages[0].code')
fi

if [ "$code" != "0" ]; then echo "[-] Contact not found (Code: $code)"; echo "$response" | jq -r '.messages[0].message'; exit 1; fi

SUB_ID=$(echo "$response" | jq -r '.response.data[0].fieldData.ID')
NAME=$(echo "$response" | jq -r '.response.data[0].fieldData["First Name"] + " " + .response.data[0].fieldData["Surname"]')
EMAIL=$(echo "$response" | jq -r '.response.data[0].fieldData.Email')
COMPANY=$(echo "$response" | jq -r '.response.data[0].fieldData["Company Station"] // .response.data[0].fieldData.Company // "Unknown"')
echo "[*] Found: $NAME ($EMAIL) — ID $SUB_ID — $COMPANY"

# 3. Pull dialogues (most recent first)
echo "[*] Fetching interaction history..."
payload=$(jq -n --arg id "=$SUB_ID" '{query: [{"Subscriber ID": $id}], limit: 100, sort: [{fieldName: "Contact Date", sortOrder: "descend"}]}')
resp_d=$(curl -s -X POST "$API_FIND_DIALOGUES" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$payload")
dcode=$(echo "$resp_d" | jq -r '.messages[0].code')
count=$(echo "$resp_d" | jq -r '.response.data | length // 0')

# 4. Write raw JSON (with contact header) + readable txt
jq -n --arg name "$NAME" --arg email "$EMAIL" --arg id "$SUB_ID" --arg company "$COMPANY" \
      --argjson dialogues "$(echo "$resp_d" | jq '.response.data // []')" \
   '{contact: {name: $name, email: $email, id: $id, company: $company}, count: ($dialogues|length), dialogues: $dialogues}' > "$OUT_JSON"

{
  echo "INTERACTION HISTORY — $NAME ($EMAIL) — $COMPANY — ID $SUB_ID"
  echo "Records: $count"
  echo "Generated: $(date)"
  echo "================================================================"
  echo "$resp_d" | jq -r '.response.data[]? | .fieldData as $f
     | "DATE: " + ($f["Contact Date"] // "")
     + "\nBY:   " + (($f["Account Manager"] // "") | tostring)
     + "\nTYPE: " + (($f["Contact Type"] // $f["Subject"] // "") | tostring)
     + "\nNOTE: " + (($f["Dialogue"] // "") | tostring)
     + "\n----------------------------------------------------------------"'
} > "$OUT_TXT"

echo "[+] Wrote $count records to $OUT_JSON and $OUT_TXT"
