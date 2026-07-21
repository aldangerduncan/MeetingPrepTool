#!/bin/bash

# Configuration
HOST="https://fms14.filemakerstudio.com.au"
DATABASE="IRD Subscribing Contacts"
TOKEN_FILE="/tmp/fms_token.txt"
OPENAI_KEY_FILE="./.openai_key"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

clear
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}       Meeting Preparation Tool - Interactive       ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# 1. Authentication
# Check if we have a valid token (simple check: does file exist?)
# In a real app we'd validate it, but here we'll just ask if missing.

TOKEN=""
if [ -f "$TOKEN_FILE" ]; then
    TOKEN=$(cat "$TOKEN_FILE")
    # echo "Found existing token..."
fi

if [ -z "$TOKEN" ]; then
    echo -e "${GREEN}Authentication Required${NC}"
    echo "Please enter your FileMaker credentials."
    read -p "Username: " USERNAME
    read -s -p "Password: " PASSWORD
    echo ""
    echo ""
    echo "Logging in..."

    # Base64 encode
    encoded_credentials=$(echo -n "$USERNAME:$PASSWORD" | base64)
    encoded_db=$(echo "$DATABASE" | jq -Rr @uri)
    URL="$HOST/fmi/data/v1/databases/$encoded_db/sessions"

    response=$(curl -s -X POST "$URL" \
         -H "Content-Type: application/json" \
         -H "Authorization: Basic $encoded_credentials" \
         -d '{}')

    TOKEN=$(echo "$response" | jq -r '.response.token')
    
    if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
        echo -e "${RED}Login Failed!${NC}"
        echo "Response: $response"
        exit 1
    fi
    
    echo -e "${GREEN}Login Successful!${NC}"
    echo "$TOKEN" > "$TOKEN_FILE"
fi

# 2. Main Loop
while true; do
    echo ""
    echo -e "${BLUE}----------------------------------------------------${NC}"
    echo "Who are you meeting with?"
    echo "(Enter Name or Email, or type 'exit' to quit)"
    read -p "> " QUERY

    if [[ "$QUERY" == "exit" ]]; then
        echo "Goodbye!"
        break
    fi

    if [ -z "$QUERY" ]; then
        continue
    fi


    echo ""
    
    # Load OpenAI Key if available
    OPENAI_KEY=""
    if [ -f "$OPENAI_KEY_FILE" ]; then
        OPENAI_KEY=$(cat "$OPENAI_KEY_FILE")
    fi

    # Call the existing logic script
    ./meeting_prep.sh "$QUERY" "$TOKEN" "$OPENAI_KEY"

    # Check for expired token error from the sub-script
    # (Capture exit code? Or just watch output. meeting_prep.sh returns 1 on auth fail)
    ret_code=$?
    if [ $ret_code -eq 1 ]; then
        echo -e "${RED}Session may have expired. Re-authenticating...${NC}"
        rm "$TOKEN_FILE"
        TOKEN=""
        # Recursively call self or just exit and ask user to restart? 
        # Simpler to exit for simpler bash logic.
        echo "Please run './start.sh' again to log in."
        exit 1
    fi
done
