# MeetingPrepTool

Automated daily sales intelligence for IRD Group / Prospector. Each weekday morning the VPS sends two emails:

| Email | Time (Sydney) | What it contains |
|-------|--------------|-----------------|
| **Daily Huddle** | 7:30am | Yesterday's FileMaker stats, today's calendar, top Prospector insights |
| **Meeting Prep** | 8:00am | Per-attendee briefings for each external meeting today |

---

## Architecture

```
VPS (216.250.118.221)
├── RunDailyHuddle.command      → cron 7:30am Mon–Fri
├── prep_todays_meetings.sh     → cron 8:00am Mon–Fri
└── insights-api (port 5001)    → serves /daily-insights endpoint

Data sources
├── FileMaker (fms14.filemakerstudio.com.au)  → CRM stats & contact records
├── Google Apps Script (CalendarWebApp.js)    → calendar events & email delivery
├── Prospector API                            → industry insights
└── OpenAI GPT-4o                            → briefing generation & insight selection
```

---

## Repository Contents

| File | Purpose |
|------|---------|
| `RunDailyHuddle.command` | Daily Huddle report — stats, calendar, insights |
| `prep_todays_meetings.sh` | Meeting Prep emails — one per external meeting |
| `meeting_prep.sh` | Per-attendee briefing generator |
| `fm_stats.sh` | Pulls yesterday's activity stats from FileMaker |
| `get_calendar_events.sh` | Fetches today's calendar via Google Apps Script |
| `analyze_prospector_insights.py` | Fetches and AI-ranks Prospector insights |
| `get_token.sh` | Manages FileMaker auth tokens |
| `CalendarWebApp.js` | Google Apps Script (deploy to your own account) |
| `update_vps_schedule.sh` | Deploy script — syncs code, timezone, and cron to VPS |
| `email_meeting_prep.sh` | On-demand meeting prep triggered via SSH |
| `CloudKeyContact.command` | Runs key contact prep remotely via SSH |

---

## Secrets (not in repo)

Three files must be present in the working directory but are excluded from version control:

| File | Contents |
|------|---------|
| `.openai_key` | OpenAI API key |
| `.fm_creds` | FileMaker username and password |
| `.apify_key` | Apify API key (LinkedIn scraping) |

---

## Deploying / Updating the VPS

Every push to `main` automatically deploys to the VPS via the GitHub Action in `.github/workflows/deploy.yml`. The action SSHes into the VPS and runs `git pull origin main`.

To trigger a deploy manually without making a code change:
```bash
gh workflow run "Deploy to VPS" --repo aldangerduncan/MeetingPrepTool
```

### First-time VPS setup

If setting up a new VPS, run this once from your local machine to configure the timezone, cron schedule, and sync secrets:

```bash
./update_vps_schedule.sh
```

This will:
1. Copy secrets (`.fm_creds`, `.openai_key`, `.apify_key`) to the VPS
2. Pull the latest code from GitHub
3. Set the VPS timezone to `Australia/Sydney`
4. Rebuild the cron schedule
5. Run `prep_todays_meetings.sh` immediately as a smoke test

### GitHub Action secrets required

| Secret | Value |
|--------|-------|
| `VPS_HOST` | VPS IP address |
| `VPS_USER` | `root` |
| `VPS_SSH_KEY` | Private SSH key (public key must be in VPS `~/.ssh/authorized_keys`) |
| `VPS_REPO_PATH` | Path to repo on VPS (e.g. `/root/MeetingPrep`) |

---

## Adding a New User

See [COLLEAGUE_SETUP.md](COLLEAGUE_SETUP.md) for the full step-by-step guide (~1 hour).
