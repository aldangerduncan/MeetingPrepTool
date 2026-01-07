#!/bin/bash

# 1. Setup Environment
# Ensure we are in the script's directory
cd "$(dirname "$0")"

# Configuration
TOKEN_FILE="/tmp/fms_token.txt"
OPENAI_KEY_FILE="./.openai_key"
HOST="https://fms14.filemakerstudio.com.au"
DATABASE="IRD Subscribing Contacts"

# Helper function for GUI Dialogs
gui_input() {
    osascript -e "text returned of (display dialog \"$1\" default answer \"\" buttons {\"OK\", \"Cancel\"} default button \"OK\" with title \"Meeting Prep Tool\")"
}

gui_password() {
    osascript -e "text returned of (display dialog \"$1\" default answer \"\" buttons {\"OK\", \"Cancel\"} default button \"OK\" with title \"Meeting Prep Tool\" with hidden answer)"
}

gui_alert() {
    osascript -e "display dialog \"$1\" buttons {\"OK\"} default button \"OK\" with title \"Meeting Prep Tool\" with icon note"
}

# 2. Authentication Check
TOKEN=""
if [ -f "$TOKEN_FILE" ]; then
    TOKEN=$(cat "$TOKEN_FILE")
fi

# Basic check if token needs refresh (naive check, real check happens on failure)
if [ -z "$TOKEN" ]; then
    USERNAME=$(gui_input "Please enter your FileMaker Username:") || exit 0
    PASSWORD=$(gui_password "Please enter your FileMaker Password:") || exit 0
    
    encoded_credentials=$(echo -n "$USERNAME:$PASSWORD" | base64)
    encoded_db=$(echo "$DATABASE" | jq -Rr @uri)
    URL="$HOST/fmi/data/v1/databases/$encoded_db/sessions"

    response=$(curl -s -X POST "$URL" \
         -H "Content-Type: application/json" \
         -H "Authorization: Basic $encoded_credentials" \
         -d '{}')

    TOKEN=$(echo "$response" | jq -r '.response.token')
    
    if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
        gui_alert "Login Failed. Please try again."
        exit 1
    fi
    echo "$TOKEN" > "$TOKEN_FILE"
fi

# 3. Get User Input
QUERY=$(gui_input "Who are you meeting with? (Name or Email)")
if [ -z "$QUERY" ]; then
    exit 0
fi

# 4. Run Search & Capture Output
# We call the existing script to do the heavy lifting
# But we need to handle the OpenAI Key passing
OPENAI_KEY=""
if [ -f "$OPENAI_KEY_FILE" ]; then
    OPENAI_KEY=$(cat "$OPENAI_KEY_FILE")
fi

# Use a temp file for the raw output
OUTPUT_FILE="/tmp/meeting_prep_raw.txt"
./meeting_prep.sh "$QUERY" "$TOKEN" "$OPENAI_KEY" > "$OUTPUT_FILE"

# Check exit code to catch Token Errors (952)
RET_CODE=$?
if [ $RET_CODE -eq 1 ]; then
    # Start.sh handled this logic interactively, we need to handle it GUI-wise
    # Check if it was a token error
    if grep -q "Code 952" "$OUTPUT_FILE"; then
         # Invalidate token and restart (simple recursion or just alert)
         rm "$TOKEN_FILE"
         gui_alert "Session Expired. Please run the tool again to log in."
         exit 0
    else
         # Other error
         gui_alert "An error occurred. Check the raw output?"
    fi
fi

# 5. Generate HTML Report
# 5. Generate HTML Report
HTML_FILE="Meeting_Report_$(date +%s).html"
DATE_STR=$(date)

# Read Raw Output
RAW_CONTENT=$(cat "$OUTPUT_FILE")

# Extract Metadata for "Chips"
# We look for the "Context:" line we added in meeting_prep.sh
# Expected format: "Context: Existing Client (Prospector)"
CTX_LINE=$(grep "Context:" "$OUTPUT_FILE" | head -n 1)
CTX_STATUS=$(echo "$CTX_LINE" | awk -F': ' '{print $2}' | awk -F' (' '{print $1}')
CTX_PRODUCT=$(echo "$CTX_LINE" | awk -F'(' '{print $2}' | tr -d ')')

# If missing, default
[ -z "$CTX_STATUS" ] && CTX_STATUS="Unknown Status"
[ -z "$CTX_PRODUCT" ] && CTX_PRODUCT="Unknown Product"

# Extract LinkedIn Headline if available (Scan for "Headline: ")
LINKEDIN_HEADLINE=$(grep "Headline:" "$OUTPUT_FILE" | head -n 1 | sed 's/Headline: //')
[ -z "$LINKEDIN_HEADLINE" ] && LINKEDIN_HEADLINE="Key Contact"

# Split Content (Summary vs Raw)
# We use Python/Ruby or just robust sed to ensure we don't break JS strings
# Simplest way for bash: Extract summary text, base64 encode it to avoid quote issues, then decode in JS.

SUMMARY_TEXT=$(echo "$RAW_CONTENT" | sed -n '/MEETING PREPARATION BRIEF:/,$p' | sed '1,4d')
RAW_LOG_TEXT="$RAW_CONTENT"

# Helper to escape for JS backticks
# Actually, base64 is safer to transport to JS
SUMMARY_B64=$(echo "$SUMMARY_TEXT" | base64)
RAW_B64=$(echo "$RAW_LOG_TEXT" | base64)

# Create HTML
cat <<EOF > "$HTML_FILE"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Meeting Prep: $QUERY</title>
  <style>
    :root{
      --bg:#f6f7f9;
      --card:#ffffff;
      --text:#111827;
      --muted:#6b7280;
      --border:#e5e7eb;
      --accent:#1f6feb;
      --shadow:0 1px 2px rgba(16,24,40,.06), 0 10px 24px rgba(16,24,40,.10);
      --radius:16px;
    }
    *{ box-sizing:border-box; }
    body{
      margin:0;
      background:var(--bg);
      color:var(--text);
      font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,"Apple Color Emoji","Segoe UI Emoji";
      font-size:16px;
      line-height:1.6;
      -webkit-font-smoothing:antialiased;
      text-rendering:optimizeLegibility;
    }
    .wrap{ max-width:980px; margin:0 auto; padding:28px 18px 44px; }
    .header{ display:flex; flex-direction:column; gap:10px; margin-bottom:16px; }
    .title{ font-size:30px; line-height:1.15; letter-spacing:-.02em; margin:0; }
    .sub{ color:var(--muted); margin:0; }
    .chips{ display:flex; flex-wrap:wrap; gap:8px; margin-top:6px; }
    .chip{
      display:inline-flex; align-items:center; gap:6px;
      padding:6px 10px; border-radius:999px;
      border:1px solid var(--border);
      background:#f8fafc; color:var(--muted); font-size:12px;
    }
    .chip strong{ color:var(--text); font-weight:600; }
    .grid{ display:grid; grid-template-columns:1fr; gap:14px; margin-top:14px; }
    /* @media (min-width:900px){ .grid.two{ grid-template-columns:1.2fr .8fr; } } */ 
    /* Simplified to 1 column for now unless we parse specific sections */
    
    .card{
      background:var(--card);
      border:1px solid var(--border);
      border-radius:var(--radius);
      box-shadow:var(--shadow);
      padding:24px;
    }
    .card h2{ font-size:18px; margin:0 0 16px; letter-spacing:-.01em; color:var(--accent); }
    
    /* Markdown rendering */
    .md p{ margin:0 0 12px; }
    .md ul{ margin:8px 0 16px 20px; padding:0; }
    .md li{ margin:6px 0; }
    .md strong{ color:var(--text); font-weight:700; }
    
    details{ margin-top:10px; }
    summary{ cursor:pointer; color:var(--accent); font-weight:600; list-style:none; }
    summary::-webkit-details-marker{ display:none; }
    .raw{
      background:#0b1220;
      color:#e5e7eb;
      border-radius:12px;
      padding:12px 14px;
      overflow-x:auto;
      white-space:pre-wrap;
      font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace;
      font-size:12.5px;
      line-height:1.55;
      border:1px solid rgba(255,255,255,.08);
    }
    .footer{ margin-top:18px; text-align:center; color:var(--muted); font-size:12px; }
  </style>
</head>
<body>
  <div class="wrap">
    <header class="header">
      <h1 class="title">Meeting Prep: $QUERY</h1>
      <div class="chips">
        <span class="chip"><strong>Status:</strong> $CTX_STATUS</span>
        <span class="chip"><strong>Product:</strong> $CTX_PRODUCT</span>
        <span class="chip"><strong>Role:</strong> $LINKEDIN_HEADLINE</span>
      </div>
    </header>

    <div class="grid">
      <section class="card">
        <h2>Start assessment / AI brief</h2>
        <div class="md" id="markdown-content"></div>
      </section>

      <section class="card">
        <h2>Raw data / full log</h2>
        <details>
          <summary>Show raw log</summary>
          <div class="raw" id="raw-log"></div>
        </details>
      </section>
    </div>

    <div class="footer">Generated by Antigravity Meeting Prep Tool at $DATE_STR</div>
  </div>

  <script>
    // Decoders
    const b64DecodeUnicode = (str) => {
        // Going backwards: from bytestream, to percent-encoding, to original string.
        return decodeURIComponent(Array.prototype.map.call(atob(str), function(c) {
            return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
        }).join(''));
    };

    const summaryB64 = "$SUMMARY_B64";
    const rawB64 = "$RAW_B64";

    const summaryText = b64DecodeUnicode(summaryB64);
    const rawText = b64DecodeUnicode(rawB64);

    // Lightweight markdown renderer
    function renderMarkdown(md){
      md = md.replace(/\r\n/g, "\n");
      
      // Escape HTML
      md = md.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

      // Bold **text**
      md = md.replace(/\*\*(.+?)\*\*/g, "<strong>\$1</strong>");
      
      // Headers ###
      md = md.replace(/^### (.*$)/gm, "<h3>\$1</h3>");
      md = md.replace(/^## (.*$)/gm, "<h2>\$1</h2>");

      const lines = md.split("\n");
      let out = "";
      let inList = false;

      for (const line of lines){
        const trimmed = line.trim();
        const isBullet = /^[-*]\s+/.test(trimmed);

        if (isBullet){
          if (!inList){ out += "<ul>"; inList = true; }
          out += "<li>" + trimmed.replace(/^[-*]\s+/, "") + "</li>";
        } else {
          if (inList){ out += "</ul>"; inList = false; }
          if (trimmed === "") continue;

          // Treat some “label lines” as bold (keeps it scannable)
          if (/^\d+\./.test(trimmed) || /^[A-Za-z].*:\s*$/.test(trimmed)){
            out += "<p><strong>" + trimmed + "</strong></p>";
          } else {
            out += "<p>" + trimmed + "</p>";
          }
        }
      }
      if (inList) out += "</ul>";
      return out;
    }

    document.getElementById("markdown-content").innerHTML = renderMarkdown(summaryText);
    document.getElementById("raw-log").textContent = rawText.trim();
  </script>
</body>
</html>
EOF

# 6. Open in Browser
open "$HTML_FILE"
