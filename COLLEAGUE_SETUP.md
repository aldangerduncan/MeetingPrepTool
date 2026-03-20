# Meeting Prep Tool — New User Setup Guide

This guide covers everything needed to install the Meeting Prep and Key Contact apps on a new laptop. Estimated setup time: **1–1.5 hours** (spread across one sitting, with some waiting time for downloads).

---

## What These Apps Do

| App | What it does |
|-----|-------------|
| **Meeting Prep** | Before each meeting, auto-generates a briefing on who you're meeting, pulled from their LinkedIn and CRM — and emails it to you |
| **Key Contact** | On-demand deep-dive on any contact — enriches their profile using LinkedIn and email history |

---

## What the New User Needs

Before starting, the following accounts/items must be in place:

| Item | Who provides it |
|------|----------------|
| OpenAI API key | New user creates their own at [platform.openai.com](https://platform.openai.com) (~$5–10/month in usage) |
| FileMaker login | Shared — Alex's login can be used |
| Google account | New user's existing work Google/Gmail account |

---

## Step-by-Step Setup

---

### Step 1 — Install Developer Tools

**Estimated time: 20–40 minutes** (mostly waiting for downloads)

These are standard macOS developer tools. They don't require admin permissions to install.

Open **Terminal** (Spotlight → type "Terminal") and run these commands one at a time. Wait for each one to fully finish before running the next.

```
xcode-select --install
```
> A popup will appear — click **Install**. This can take 10–20 minutes depending on internet speed.

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
> This installs Homebrew, a standard macOS package manager. Follow any on-screen prompts. Takes around 5–10 minutes.

```
brew install jq
```
> A small tool the apps depend on. Takes 1–2 minutes.

---

### Step 2 — Download the App Code

**Estimated time: 2–5 minutes**

In Terminal, run:

```
git clone https://github.com/aldangerduncan/MeetingPrepTool.git ~/Documents/GitHub/MeetingPrepTool
```

This downloads the latest version of the apps onto the laptop.

---

### Step 3 — Add API Keys and Credentials

**Estimated time: 10–15 minutes**

Two small text files need to be manually placed in the app folder. These files are **not** stored on GitHub for security reasons.

**File 1: OpenAI API Key**
- The new user signs up at [platform.openai.com](https://platform.openai.com)
- Creates an API key
- Saves it in a file called `.openai_key` inside `~/Documents/GitHub/MeetingPrepTool/`

**File 2: FileMaker Credentials**
- Alex copies the `.fm_creds` file from his own machine and sends it to the new user securely
- The new user places it in `~/Documents/GitHub/MeetingPrepTool/`

> These files are hidden (start with `.`) and are excluded from version control. They never leave the laptop.

---

### Step 4 — Set Up Google Calendar Integration

**Estimated time: 20–30 minutes**

Meeting Prep reads today's calendar and emails the report via a small Google Apps Script — a free script that runs inside the new user's own Google account.

**4a.** Go to [script.google.com](https://script.google.com) while logged into their **work Google account**

**4b.** Click **New Project**

**4c.** Delete all existing content in the editor and paste in the contents of the file `CalendarWebApp.js` from the app folder

**4d.** Find and replace every instance of `alex.sheath@irdgroup.com.au` with the new user's email address (there are 3 occurrences)

**4e.** Enable the Calendar API:
- Click the **`+`** icon next to **Services** in the left panel
- Find **Google Calendar API** and click **Add**

**4f.** Deploy the script:
- Click **Deploy** → **New Deployment**
- Type: **Web App**
- Who has access: **Anyone**
- Click **Deploy** → **Authorise** (grant the permissions it requests)
- **Copy the URL** it gives you — you'll need it in Step 4g

**4g.** Update the app config with the new URL:
- Open Terminal and run the following (replace `PASTE_URL_HERE` with the URL from Step 4f):

```
NEW_URL="PASTE_URL_HERE"
cd ~/Documents/GitHub/MeetingPrepTool
sed -i '' "s|https://script.google.com/macros/s/AKfycbxhH0lpZ3tq6KZovVQV8UpJubi74EloknJRQzYfDiV7yfAr585sdw_OGNPzCMkzjAlG/exec|$NEW_URL|g" \
  prep_todays_meetings.sh email_meeting_prep.sh
```

---

### Step 5 — Set Up Auto-Updates

**Estimated time: 2 minutes**

This installs a background task that automatically keeps the app code up to date whenever a new version is pushed (no manual updating needed).

In Terminal, run:

```
bash ~/Documents/GitHub/MeetingPrepTool/install_launchagent.sh
```

---

### Step 6 — Test the Apps

**Estimated time: 10–15 minutes**

Run each app once to confirm everything is working:

**Meeting Prep:**
```
bash ~/Documents/GitHub/MeetingPrepTool/prep_todays_meetings.sh
```
> This should generate a meeting briefing and email it to the new user. If there are no meetings today, it will say so.

**Key Contact (replace email with a real contact):**
```
bash ~/Documents/GitHub/MeetingPrepTool/KeyContactPrep.command someone@example.com
```
> Replace `someone@example.com` with a real contact's email address.

---

## Summary of Ongoing Costs

| Service | Cost |
|---------|------|
| OpenAI API | ~$5–15/month (pay as you go, based on usage) |
| FileMaker | Already licensed — shared login |
| Google Apps Script | Free (included with Google account) |

---

## Who to Contact for Help

If any step fails, contact Alex Sheath — the app code and configuration are managed by him.
