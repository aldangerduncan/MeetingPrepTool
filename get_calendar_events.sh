#!/bin/bash

# Fetch Calendar Events via Google Apps Script Web App
# URL: https://script.google.com/macros/s/AKfycbxhH0lpZ3tq6KZovVQV8UpJubi74EloknJRQzYfDiV7yfAr585sdw_OGNPzCMkzjAlG/exec
# Output: Formatted text list

WEB_APP_URL="https://script.google.com/macros/s/AKfycbxhH0lpZ3tq6KZovVQV8UpJubi74EloknJRQzYfDiV7yfAr585sdw_OGNPzCMkzjAlG/exec"

# Fetch JSON (follow redirects with -L)
RESPONSE=$(curl -L -s "$WEB_APP_URL")

# Check if curl failed or returned empty
if [ -z "$RESPONSE" ]; then
    echo "Error: Failed to fetch calendar data."
    exit 1
fi

# Use jq to format the output matches the previous style
# Format: "• DD/MM/YYYY HH:MM: Title (emails)"
# Format: HTML <div class="calendar-item">...</div>
# shortDate is "d MMM yyyy HH:mm"
# We define "Today" string to separate lists
TODAY_STR=$(date "+%-d %b %Y")

# Determine correct label for "Yesterday" section
LABEL="Yesterday"
if [ "$(date +%u)" -eq 1 ]; then
    LABEL="Last Friday"
fi

echo "$RESPONSE" | jq -r --arg today "$TODAY_STR" --arg label "$LABEL" '
  def html_item:
    "<div class=\"calendar-item\">
       <div style=\"display:flex; justify-content:space-between; align-items:center;\">
         <div>
           <div class=\"calendar-time\">" + .shortDate + "</div>
           <div><strong>" + .title + "</strong></div>
           <div class=\"calendar-meta\">With: " + (.attendees | join(", ")) + "</div>
         </div>" +
       (if .googleMeetUrl != "" and (.shortDate | startswith($today)) then
          "<div>
             <a href=\"https://script.google.com/macros/s/AKfycbxhH0lpZ3tq6KZovVQV8UpJubi74EloknJRQzYfDiV7yfAr585sdw_OGNPzCMkzjAlG/exec?action=schedule&email=" + (.attendees[0] // "") + "&name=" + (.title | @uri) + "&time=" + (.timeOnly | @uri) + "&meetUrl=" + (.googleMeetUrl | @uri) + "\" target=\"_blank\" style=\"background:#2980b9; color:white; padding:6px 12px; border-radius:4px; text-decoration:none; font-size:12px; display:inline-block;\">
               🔔 Remind
             </a>
           </div>"
        else "" end) + "
       </div>
     </div>";

  (.events | map(select(.shortDate | startswith($today) | not))) as $yesterday
  | (.events | map(select(.shortDate | startswith($today)))) as $today_evs

  | (if ($yesterday | length) > 0 then
       "<h3 style=\"margin:16px 0 8px; font-size:0.9rem; color:#7f8c8d; text-transform:uppercase; letter-spacing:0.05em;\">" + $label + "</h3>" + 
       ($yesterday | map(html_item) | join(""))
     else "" end)
  + (if ($today_evs | length) > 0 then
       "<h3 style=\"margin:16px 0 8px; font-size:0.9rem; color:#7f8c8d; text-transform:uppercase; letter-spacing:0.05em;\">Today</h3>" + 
       ($today_evs | map(html_item) | join(""))
     else "" end)
'

