#!/bin/bash

# --- Daily Huddle Automation (HTML) ---

# 1. Set Working Directory
cd "$(dirname "$0")" || exit 1

# 2. Get Statistics (FileMaker)
FM_STATS=$(./fm_stats.sh)

# 3. Get Calendar Events (AppleScript)
CAL_EVENTS=$(./get_calendar_events.sh)

# 4. Get Email Insights (AI)
EMAIL_INSIGHTS=$(python3 analyze_email.py)

# 5. Build HTML Report
TODAY_FULL=$(date "+%-d %b %Y")
# TODAY_SHORT=$(date "+%d %b %Y") # e.g. 7 Jan 2026

HTML_DIR="../DailyHuddle"
mkdir -p "$HTML_DIR"
HTML_FILE="${HTML_DIR}/DailyHuddle_${TODAY_FULL// /_}.html"

cat <<EOF > "$HTML_FILE"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Daily Huddle - $TODAY_FULL</title>

  <style>
    :root {
      --bg: #f4f6f8;
      --card: #ffffff;
      --text: #2c3e50;
      --muted: #7f8c8d;
      --accent: #e67e22;
      --border: #e0e0e0;
    }

    body {
      margin: 0;
      padding: 32px;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--text);
    }

    .container {
      max-width: 900px;
      margin: 0 auto;
    }

    header {
      margin-bottom: 32px;
    }

    header h1 {
      margin: 0;
      font-size: 2rem;
    }

    header .date {
      color: var(--muted);
      margin-top: 4px;
    }

    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 20px;
      margin-bottom: 24px;
    }

    .card h2 {
      margin: 0 0 16px 0;
      font-size: 1rem;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--accent);
    }

    /* Stats */
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 16px;
    }

    .stat {
      background: #fafafa;
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 16px;
      text-align: center;
    }

    .stat .value {
      font-size: 1.8rem;
      font-weight: 600;
    }

    .stat .label {
      margin-top: 4px;
      font-size: 0.85rem;
      color: var(--muted);
    }

    .rep {
      margin-bottom: 16px;
      font-weight: 500;
      color: var(--muted);
    }

    /* Calendar */
    .calendar-item {
      padding: 12px 0;
      border-bottom: 1px solid var(--border);
    }

    .calendar-item:last-child {
      border-bottom: none;
    }

    .calendar-time {
      font-weight: 600;
      margin-right: 8px;
      display: inline-block;
    }

    .calendar-meta {
      color: var(--muted);
      font-size: 0.9rem;
      margin-top: 4px;
    }

    /* Email insights */
    .insight {
      padding: 12px 0;
      border-bottom: 1px solid var(--border);
    }

    .insight:last-child {
      border-bottom: none;
    }

    .tag {
      display: inline-block;
      font-size: 0.7rem;
      font-weight: 600;
      padding: 4px 8px;
      border-radius: 999px;
      margin-right: 8px;
      background: #fdebd0;
      color: #b05d13;
    }

    .remind-btn {
      background: var(--accent);
      color: white;
      border: none;
      padding: 6px 12px;
      border-radius: 6px;
      font-size: 0.8rem;
      font-weight: 600;
      cursor: pointer;
      transition: opacity 0.2s;
    }

    .remind-btn:hover {
      opacity: 0.8;
    }

    .remind-btn.done {
      background: #27ae60;
      cursor: default;
    }
  </style>
</head>

<body>
  <div class="container">

    <header>
      <h1>Daily Huddle</h1>
      <div class="date">$TODAY_FULL</div>
    </header>

    <div class="card">
      <h2>Yesterday’s Stats</h2>
      <div class="rep">Sales Rep: Alex Sheath</div>

$FM_STATS
    </div>

    <div class="card">
      <h2>Calendar</h2>
$CAL_EVENTS
    </div>

    <div class="card">
      <h2>Email Insights</h2>
$EMAIL_INSIGHTS
    </div>

  </div>

  <script>
    async function scheduleReminder(email, name, time, meetUrl, btn) {
      if (btn.classList.contains('done')) return;
      btn.textContent = '...';
      const webAppUrl = "$WEB_APP_URL";
      const params = new URLSearchParams({
        action: 'schedule',
        email: email,
        name: name,
        time: time,
        meetUrl: meetUrl
      });

      try {
        await fetch(webAppUrl + '?' + params.toString(), { mode: 'no-cors' });
        btn.textContent = 'Scheduled ✅';
        btn.classList.add('done');
      } catch (err) {
        console.error(err);
        btn.textContent = 'Error';
      }
    }
  </script>
</body>
</html>
EOF

# 6. Open in Browser (if running interactively)
# Check if running in a terminal (not cron/automated)
if [ -t 1 ] || [ "$1" == "--open" ]; then
    open "$HTML_FILE"
fi

# 7. Send Email via Web App
echo "Sending Report via Email..."
WEB_APP_URL="https://script.google.com/macros/s/AKfycbxhH0lpZ3tq6KZovVQV8UpJubi74EloknJRQzYfDiV7yfAr585sdw_OGNPzCMkzjAlG/exec"

# Read HTML content safely
HTML_CONTENT=$(cat "$HTML_FILE")

# Create JSON payload using jq to handle escaping
PAYLOAD=$(jq -n --arg html "$HTML_CONTENT" --arg subj "Daily Huddle - $TODAY_FULL" '{html: $html, subject: $subj}')

# POST to Web App
RESPONSE=$(curl -L -s -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$WEB_APP_URL")

echo "Email Status: $RESPONSE"
echo "Report generated at: $HTML_FILE"
