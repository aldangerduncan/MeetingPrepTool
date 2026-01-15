#!/bin/bash

# Configuration
HOST="https://fms14.filemakerstudio.com.au"
DATABASE="IRD Subscribing Contacts"
CRED_FILE=".fm_creds"
TOKEN_FILE=".recent_token"

IS_SILENT=false
if [ "$1" == "--silent" ]; then
    IS_SILENT=true
fi

if [ "$IS_SILENT" = false ]; then
    echo "--- FileMaker Data API Token Generator ---"
    echo "Host: $HOST"
    echo "Database: $DATABASE"
    echo ""
fi

# Function to Request Token
request_token() {
    local encoded_creds="$1"
    
    # URL Encode Database Name
    local encoded_db=$(echo "$DATABASE" | jq -Rr @uri)
    local url="$HOST/fmi/data/v1/databases/$encoded_db/sessions"

    # Request
    local response=$(curl -s -X POST "$url" \
         -H "Content-Type: application/json" \
         -H "Authorization: Basic $encoded_creds" \
         -d '{}')
         
    echo "$response"
}

# --- Logic Flow ---

ENCODED_CREDS=""

# 1. Check for saved credentials if Silent Mode or if file exists
if [ -f "$CRED_FILE" ]; then
    ENCODED_CREDS=$(cat "$CRED_FILE")
fi

# 2. If no creds (or interactive forced), Prompt User
if [ -z "$ENCODED_CREDS" ]; then
    if [ "$IS_SILENT" = true ]; then
        echo "Error: No saved credentials found. Run without --silent first."
        exit 1
    fi

    read -p "Enter Username: " USERNAME
    read -s -p "Enter Password: " PASSWORD
    echo ""
    
    # Base64 Encode
    ENCODED_CREDS=$(echo -n "$USERNAME:$PASSWORD" | base64)
    
    echo ""
    read -p "Save credentials for auto-renewal? (y/n): " SAVE_CHOICE
    if [[ "$SAVE_CHOICE" =~ ^[Yy]$ ]]; then
        echo "$ENCODED_CREDS" > "$CRED_FILE"
        chmod 600 "$CRED_FILE"
        echo "[*] Credentials saved to $CRED_FILE (securely)."
    fi
    echo ""
fi

if [ "$IS_SILENT" = false ]; then
    echo "[*] Requesting Session Token..."
fi

RESPONSE=$(request_token "$ENCODED_CREDS")
TOKEN=$(echo "$RESPONSE" | jq -r '.response.token')
CODE=$(echo "$RESPONSE" | jq -r '.messages[0].code')

if [ "$CODE" == "0" ] && [ "$TOKEN" != "null" ]; then
    # Success
    echo "$TOKEN" > "$TOKEN_FILE"
    
    if [ "$IS_SILENT" = false ]; then
        echo "[+] SUCCESS! New token generated."
        echo "[*] Saved to $TOKEN_FILE"
    fi
else
    # Failure
    if [ "$IS_SILENT" = false ]; then
        echo "[-] FAILED to get token."
        echo "Response: $RESPONSE"
        echo "[!] Check your network connection or credentials in $CRED_FILE."
    fi
    exit 1
fi
